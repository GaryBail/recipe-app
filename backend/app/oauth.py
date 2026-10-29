"""Вход через VK ID и Яндекс ID (OAuth 2.0 / 2.1, код авторизации + PKCE).

Как это работает:
1. Приложение генерирует code_verifier и state, просит у сервера адрес входа: GET /auth/{provider}/start.
2. Браузер открывает страницу VK ID / Яндекс ID. После входа провайдер возвращает пользователя
   на наш адрес /auth/{provider}/callback, а сервер перенаправляет в приложение: vyborvkusa://oauth/{provider}?code=…
3. Приложение отправляет code + code_verifier на POST /auth/{provider}. Сервер обменивает код на токен
   у провайдера, узнаёт id и email пользователя и выдаёт сессию.
code_verifier остаётся в приложении, поэтому перехваченный code сам по себе бесполезен.
Секрет Яндекса хранится только на сервере.

Настройки сервера: PUBLIC_URL (https://api.example.ru), YANDEX_CLIENT_ID, YANDEX_CLIENT_SECRET, VK_CLIENT_ID.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from typing import Any
from urllib.parse import urlencode

APP_REDIRECT = "vyborvkusa://oauth"


class OAuthError(Exception):
    pass


@dataclass(frozen=True)
class Identity:
    provider: str
    subject: str
    email: str | None
    name: str | None


class _Provider:
    name = ""

    def __init__(self, client_id: str, public_url: str, http: Any = None):
        self.client_id = client_id
        self.public_url = public_url.rstrip("/")
        self._http = http

    @property
    def redirect_uri(self) -> str:
        return f"{self.public_url}/auth/oauth/{self.name}/callback"

    async def _client(self) -> Any:
        if self._http is None:
            import httpx
            self._http = httpx.AsyncClient(timeout=15, headers={"User-Agent": "VyborVkusa/1.0"})
        return self._http

    async def _json(self, method: str, url: str, **kw: Any) -> dict[str, Any]:
        client = await self._client()
        try:
            resp = await client.request(method, url, **kw)
        except Exception as e:  # сеть
            raise OAuthError(f"{self.name}: нет связи ({e})") from e
        try:
            data = resp.json()
        except ValueError as e:
            raise OAuthError(f"{self.name}: неожиданный ответ HTTP {resp.status_code}") from e
        if resp.status_code >= 400 or (isinstance(data, dict) and data.get("error")):
            detail = data.get("error_description") or data.get("error") if isinstance(data, dict) else None
            raise OAuthError(f"{self.name}: {detail or f'HTTP {resp.status_code}'}")
        return data


class YandexOAuth(_Provider):
    name = "yandex"

    def __init__(self, client_id: str, client_secret: str, public_url: str, http: Any = None):
        super().__init__(client_id, public_url, http)
        self.client_secret = client_secret

    def authorize_url(self, state: str, code_challenge: str) -> str:
        return "https://oauth.yandex.ru/authorize?" + urlencode({
            "response_type": "code", "client_id": self.client_id, "redirect_uri": self.redirect_uri,
            "state": state, "code_challenge": code_challenge, "code_challenge_method": "S256",
            "force_confirm": "no",
        })

    async def identity(self, code: str, code_verifier: str, **_: Any) -> Identity:
        token = await self._json("POST", "https://oauth.yandex.ru/token", data={
            "grant_type": "authorization_code", "code": code, "code_verifier": code_verifier,
            "client_id": self.client_id, "client_secret": self.client_secret,
        })
        access = token.get("access_token")
        if not access:
            raise OAuthError("yandex: нет access_token")
        info = await self._json("GET", "https://login.yandex.ru/info", params={"format": "json"},
                                headers={"Authorization": f"OAuth {access}"})
        # Токен должен быть выдан именно нашему приложению.
        if str(info.get("client_id", self.client_id)) != self.client_id or not info.get("id"):
            raise OAuthError("yandex: токен выдан другому приложению")
        name = info.get("display_name") or info.get("real_name") or info.get("login")
        return Identity("yandex", str(info["id"]), info.get("default_email"), name)


class VKOAuth(_Provider):
    name = "vk"
    BASE = "https://id.vk.ru"

    def authorize_url(self, state: str, code_challenge: str) -> str:
        return f"{self.BASE}/authorize?" + urlencode({
            "response_type": "code", "client_id": self.client_id, "redirect_uri": self.redirect_uri,
            "state": state, "code_challenge": code_challenge, "code_challenge_method": "S256",
            "scope": "email",
        })

    async def identity(self, code: str, code_verifier: str, device_id: str | None = None,
                       state: str | None = None, **_: Any) -> Identity:
        if not device_id:
            raise OAuthError("vk: нет device_id")
        token = await self._json("POST", f"{self.BASE}/oauth2/auth", data={
            "grant_type": "authorization_code", "code": code, "code_verifier": code_verifier,
            "redirect_uri": self.redirect_uri, "client_id": self.client_id, "device_id": device_id,
            "state": state or "",
        })
        access = token.get("access_token")
        if not access:
            raise OAuthError("vk: нет access_token")
        info = await self._json("POST", f"{self.BASE}/oauth2/user_info",
                                data={"client_id": self.client_id, "access_token": access})
        user = info.get("user") if isinstance(info.get("user"), dict) else info
        subject = user.get("user_id") or token.get("user_id")
        if not subject:
            raise OAuthError("vk: нет user_id")
        name = " ".join(x for x in (user.get("first_name"), user.get("last_name")) if x) or None
        return Identity("vk", str(subject), user.get("email") or None, name)


def providers_from_env() -> dict[str, _Provider]:
    public = os.getenv("PUBLIC_URL", "")
    result: dict[str, _Provider] = {}
    if not public:
        return result
    if os.getenv("YANDEX_CLIENT_ID") and os.getenv("YANDEX_CLIENT_SECRET"):
        result["yandex"] = YandexOAuth(os.environ["YANDEX_CLIENT_ID"], os.environ["YANDEX_CLIENT_SECRET"], public)
    if os.getenv("VK_CLIENT_ID"):
        result["vk"] = VKOAuth(os.environ["VK_CLIENT_ID"], public)
    return result


def app_redirect(provider: str, query: str) -> str:
    """Куда вернуть пользователя после входа: в приложение с теми же параметрами."""
    return f"{APP_REDIRECT}/{provider}" + (f"?{query}" if query else "")
