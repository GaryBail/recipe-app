"""Вход через Яндекс ID и VK ID: ответы провайдеров подменены (httpx.MockTransport)."""

import asyncio
import json
from urllib.parse import parse_qs, urlparse

import httpx
import pytest

from app.oauth import OAuthError, VKOAuth, YandexOAuth, app_redirect
from tests.helpers import make_client

VERIFIER = "v" * 43


def yandex_transport(client_id="ya-client", user_id="1001", email="ivan@yandex.ru"):
    calls = []

    def handler(request: httpx.Request) -> httpx.Response:
        calls.append(request)
        if request.url.host == "oauth.yandex.ru":
            form = parse_qs(request.content.decode())
            if form.get("code") != ["good"] or form.get("code_verifier") != [VERIFIER]:
                return httpx.Response(400, json={"error": "invalid_grant", "error_description": "Code has expired"})
            assert form["client_secret"] == ["secret"]
            return httpx.Response(200, json={"access_token": "ya-token", "token_type": "bearer"})
        assert request.headers["Authorization"] == "OAuth ya-token"
        return httpx.Response(200, json={"id": user_id, "login": "ivan", "client_id": client_id,
                                         "default_email": email, "display_name": "Иван"})
    return httpx.MockTransport(handler), calls


def vk_transport():
    def handler(request: httpx.Request) -> httpx.Response:
        form = parse_qs(request.content.decode())
        if request.url.path == "/oauth2/auth":
            assert form["device_id"] == ["dev-1"] and form["code_verifier"] == [VERIFIER]
            assert form["redirect_uri"] == ["https://api.test/auth/oauth/vk/callback"]
            return httpx.Response(200, json={"access_token": "vk-token", "user_id": 777, "state": "s"})
        assert request.url.path == "/oauth2/user_info" and form["access_token"] == ["vk-token"]
        return httpx.Response(200, json={"user": {"user_id": "777", "first_name": "Пётр", "last_name": "Петров",
                                                  "email": "petr@vk.com"}})
    return httpx.MockTransport(handler)


def yandex(transport):
    return YandexOAuth("ya-client", "secret", "https://api.test", http=httpx.AsyncClient(transport=transport))


def vk(transport):
    return VKOAuth("vk-client", "https://api.test", http=httpx.AsyncClient(transport=transport))


def test_authorize_urls_use_pkce_and_our_callback():
    url = urlparse(yandex(yandex_transport()[0]).authorize_url("state123", "c" * 43))
    q = parse_qs(url.query)
    assert url.netloc == "oauth.yandex.ru"
    assert q["redirect_uri"] == ["https://api.test/auth/oauth/yandex/callback"]
    assert q["code_challenge_method"] == ["S256"] and q["state"] == ["state123"]
    vk_url = urlparse(vk(vk_transport()).authorize_url("state123", "c" * 43))
    assert vk_url.netloc == "id.vk.ru" and "email" in parse_qs(vk_url.query)["scope"][0]
    assert app_redirect("vk", "code=1&state=2") == "vyborvkusa://oauth/vk?code=1&state=2"


def test_yandex_identity_and_foreign_token():
    transport, _ = yandex_transport()
    identity = asyncio.run(yandex(transport).identity("good", VERIFIER))
    assert (identity.provider, identity.subject, identity.email, identity.name) == ("yandex", "1001", "ivan@yandex.ru", "Иван")
    with pytest.raises(OAuthError):
        asyncio.run(yandex(transport).identity("bad", VERIFIER))
    foreign, _ = yandex_transport(client_id="other-app")
    with pytest.raises(OAuthError):
        asyncio.run(yandex(foreign).identity("good", VERIFIER))


def test_vk_identity():
    identity = asyncio.run(vk(vk_transport()).identity("code", VERIFIER, device_id="dev-1", state="s"))
    assert (identity.subject, identity.email, identity.name) == ("777", "petr@vk.com", "Пётр Петров")
    with pytest.raises(OAuthError):
        asyncio.run(vk(vk_transport()).identity("code", VERIFIER, device_id=None))


def test_oauth_endpoints(tmp_path):
    transport, _ = yandex_transport()
    client = make_client(tmp_path, oauth={"yandex": yandex(transport), "vk": vk(vk_transport())})
    assert client.get("/auth/oauth/providers").json() == {"providers": ["vk", "yandex"]}
    start = client.get("/auth/oauth/yandex/start", params={"state": "state123", "code_challenge": "c" * 43})
    assert start.status_code == 200 and start.json()["url"].startswith("https://oauth.yandex.ru/authorize?")
    assert client.get("/auth/oauth/ok/start", params={"state": "state123", "code_challenge": "c" * 43}).status_code == 404

    back = client.get("/auth/oauth/vk/callback?code=abc&state=state123&device_id=d", follow_redirects=False)
    assert back.status_code == 302
    assert back.headers["location"] == "vyborvkusa://oauth/vk?code=abc&state=state123&device_id=d"

    r = client.post("/auth/oauth/yandex", json={"code": "good", "code_verifier": VERIFIER})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["created"] is True and body["user"]["email"] == "ivan@yandex.ru"
    assert body["user"]["email_verified"] is True
    # повторный вход — тот же аккаунт
    again = client.post("/auth/oauth/yandex", json={"code": "good", "code_verifier": VERIFIER}).json()
    assert again["created"] is False and again["user"]["id"] == body["user"]["id"]
    me = client.get("/auth/me", headers={"Authorization": f"Bearer {again['token']}"})
    assert me.status_code == 200

    bad = client.post("/auth/oauth/yandex", json={"code": "bad", "code_verifier": VERIFIER})
    assert bad.status_code == 401 and "Не удалось войти" in bad.json()["detail"]

    vk_login = client.post("/auth/oauth/vk", json={"code": "c", "code_verifier": VERIFIER, "device_id": "dev-1",
                                                   "state": "s"})
    assert vk_login.status_code == 200 and vk_login.json()["user"]["display_name"] == "Пётр Петров"


def test_social_login_does_not_take_over_existing_email(tmp_path):
    transport, _ = yandex_transport(email="taken@example.com")
    client = make_client(tmp_path, oauth={"yandex": yandex(transport)})
    r = client.post("/auth/register", json={"email": "taken@example.com", "password": "secret123", "display_name": "А"})
    assert r.status_code == 201
    social = client.post("/auth/oauth/yandex", json={"code": "good", "code_verifier": VERIFIER}).json()
    assert social["user"]["id"] != r.json()["user"]["id"]
    assert social["user"]["email"] is None


def test_not_configured(tmp_path):
    client = make_client(tmp_path)
    assert client.get("/auth/oauth/providers").json() == {"providers": []}
    assert client.post("/auth/oauth/vk", json={"code": "c", "code_verifier": VERIFIER}).status_code == 404

