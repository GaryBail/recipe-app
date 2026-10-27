"""HTTP API для iOS-приложения: цены, аккаунты, сообщество, уведомления.

Запуск: uvicorn app.main:app --host 0.0.0.0 --port 8000
"""

from __future__ import annotations

import asyncio
import logging
import os
from contextlib import asynccontextmanager
from dataclasses import dataclass
from typing import Any

from fastapi import APIRouter, BackgroundTasks, Depends, FastAPI, Header, HTTPException
from pydantic import BaseModel, Field

from .auth import (AppleLoginIn, AppleTokenError, AppleTokenVerifier, AuthStore, EmailTaken, LoginIn,
                   ProfileUpdateIn, RegisterIn)
from .community import BlockIn, CommunityStore, PublishIn, RatingIn, ReportIn, open_db
from .models import CartLineRequest
from .notifications import APNsPush, DeviceIn, MarkReadIn, NoopPush, NotificationStore, PushSender, describe
from .service import CITIES, PriceService
from .stores.base import StoreAdapter

log = logging.getLogger(__name__)


class LineIn(BaseModel):
    product_id: str
    query: str = Field(min_length=2)
    required_amount: float = Field(gt=0)
    unit: str = Field(pattern="^(g|ml|pcs)$")


class OffersIn(BaseModel):
    store: str
    city: str
    lines: list[LineIn]


@dataclass
class Stores:
    auth: AuthStore
    community: CommunityStore
    notifications: NotificationStore
    apple: AppleTokenVerifier
    push: PushSender


def default_adapters() -> list[StoreAdapter]:
    from .stores.perekrestok import PerekrestokAdapter
    from .stores.pyaterochka import PyaterochkaAdapter

    headless = os.getenv("HEADLESS", "1") != "0"
    return [PerekrestokAdapter(headless=headless), PyaterochkaAdapter(headless=headless)]


def push_from_env() -> PushSender:
    key = os.getenv("APNS_KEY_PATH")
    if not key:
        return NoopPush()
    return APNsPush(key_path=key, key_id=os.environ["APNS_KEY_ID"], team_id=os.environ["APNS_TEAM_ID"],
                    topic=os.getenv("APPLE_BUNDLE_ID", "com.garybail.recipeapp"),
                    sandbox=os.getenv("APNS_SANDBOX", "1") != "0")


# ---------- Аккаунты ----------

def _bearer(authorization: str | None) -> str | None:
    if authorization and authorization.lower().startswith("bearer "):
        return authorization[7:].strip() or None
    return None


def auth_router(s: Stores, current_user, token_dep) -> APIRouter:
    r = APIRouter(prefix="/auth", tags=["auth"])

    def session(user: dict, token: str, created: bool = False) -> dict:
        return {"token": token, "user": user, "created": created}

    @r.post("/register", status_code=201)
    async def register(body: RegisterIn):
        try:
            user, token = s.auth.register(body)
        except EmailTaken:
            raise HTTPException(409, "Этот email уже зарегистрирован")
        return session(user, token, created=True)

    @r.post("/login")
    async def login(body: LoginIn):
        result = await asyncio.to_thread(s.auth.login, body.email, body.password)
        if result is None:
            raise HTTPException(401, "Неверный email или пароль")
        return session(*result)

    @r.post("/apple")
    async def apple(body: AppleLoginIn):
        try:
            claims = await asyncio.to_thread(s.apple.verify, body.identity_token)
        except AppleTokenError as e:
            raise HTTPException(401, f"Не удалось проверить вход через Apple: {e}")
        user, token, created = s.auth.apple_login(claims["sub"], claims.get("email"), body.display_name)
        return session(user, token, created)

    @r.get("/me")
    async def me(user: dict = Depends(current_user)):
        return user

    @r.patch("/me")
    async def update_me(body: ProfileUpdateIn, user: dict = Depends(current_user)):
        updated = s.auth.update(user["id"], body)
        if body.display_name is not None:
            s.community.rename_user(user["id"], updated["display_name"])
        return updated

    @r.post("/logout", status_code=204)
    async def logout(token: str = Depends(token_dep)):
        s.auth.logout(token)

    @r.delete("/me", status_code=204)
    async def delete_me(user: dict = Depends(current_user)):
        """Удаление аккаунта и всего контента пользователя (требование App Store)."""
        s.community.delete_user_content(user["id"])
        s.notifications.delete_user(user["id"])
        s.auth.delete(user["id"])

    return r


# ---------- Сообщество ----------

def community_router(s: Stores, current_user, optional_user) -> APIRouter:
    r = APIRouter(prefix="/community", tags=["community"])

    def me(user: dict | None) -> str:
        return user["id"] if user else ""

    def found(build_id: str, user_id: str) -> dict:
        build = s.community.get(build_id, user_id)
        if build is None:
            raise HTTPException(404, "Сборка не найдена")
        return build

    @r.get("/builds")
    async def list_builds(recipe_id: str | None = None, sort: str = "top", mine: bool = False, limit: int = 50,
                          user: dict | None = Depends(optional_user)):
        if sort not in ("top", "new"):
            raise HTTPException(422, "sort: top | new")
        if mine and user is None:
            raise HTTPException(401, "Войдите, чтобы увидеть свои сборки")
        return s.community.list(me(user), recipe_id=recipe_id, sort=sort, mine=mine, limit=max(1, min(limit, 100)))

    @r.post("/builds", status_code=201)
    async def publish(body: PublishIn, user: dict = Depends(current_user)):
        return s.community.publish(user["id"], user["display_name"], body)

    @r.get("/builds/{build_id}")
    async def get_build(build_id: str, user: dict | None = Depends(optional_user)):
        return found(build_id, me(user))

    @r.delete("/builds/{build_id}", status_code=204)
    async def delete_build(build_id: str, user: dict = Depends(current_user)):
        if not s.community.delete(build_id, user["id"]):
            raise HTTPException(404, "Сборка не найдена или принадлежит другому пользователю")

    @r.get("/builds/{build_id}/ratings")
    async def ratings(build_id: str, user: dict | None = Depends(optional_user)):
        found(build_id, me(user))
        return s.community.ratings(build_id, me(user))

    @r.put("/builds/{build_id}/rating")
    async def rate(build_id: str, body: RatingIn, background: BackgroundTasks,
                   user: dict = Depends(current_user)):
        build = found(build_id, user["id"])
        if build["author_id"] == user["id"]:
            raise HTTPException(403, "Нельзя оценивать свою сборку")
        s.community.rate(build_id, user["id"], user["display_name"], body)

        kind = "comment" if body.comment else "rating"
        s.notifications.add(build["author_id"], kind, build_id, build["name"], user["id"],
                            user["display_name"], body.stars, body.comment)
        background.add_task(send_push, s, build["author_id"], kind, build_id, build["name"],
                            user["display_name"], body.stars, body.comment)
        return found(build_id, user["id"])

    @r.post("/builds/{build_id}/report", status_code=204)
    async def report(build_id: str, body: ReportIn, user: dict = Depends(current_user)):
        found(build_id, user["id"])
        s.community.report(build_id, user["id"], body.reason)

    @r.post("/blocks", status_code=204)
    async def block(body: BlockIn, user: dict = Depends(current_user)):
        if body.user_id == user["id"]:
            raise HTTPException(422, "Нельзя заблокировать себя")
        s.community.block(user["id"], body.user_id)

    return r


async def send_push(s: Stores, user_id: str, kind: str, build_id: str, build_name: str,
                    actor: str, stars: int | None, comment: str | None) -> None:
    tokens = s.notifications.devices(user_id)
    if not tokens:
        return
    title, text = describe(kind, actor, build_name, stars, comment)
    try:
        invalid = await s.push.send(tokens, title, text, s.notifications.unread_count(user_id),
                                    {"build_id": build_id, "kind": kind})
    except Exception:
        log.exception("push failed")
        return
    for token in invalid:
        s.notifications.remove_device(token)


# ---------- Уведомления ----------

def notifications_router(s: Stores, current_user) -> APIRouter:
    r = APIRouter(tags=["notifications"])

    @r.get("/notifications")
    async def list_notifications(user: dict = Depends(current_user)):
        return {"items": s.notifications.list(user["id"]), "unread_count": s.notifications.unread_count(user["id"])}

    @r.post("/notifications/read", status_code=204)
    async def mark_read(body: MarkReadIn, user: dict = Depends(current_user)):
        s.notifications.mark_read(user["id"], body.ids)

    @r.post("/devices", status_code=204)
    async def add_device(body: DeviceIn, user: dict = Depends(current_user)):
        s.notifications.add_device(user["id"], body.token)

    @r.delete("/devices/{token}", status_code=204)
    async def remove_device(token: str, user: dict = Depends(current_user)):
        s.notifications.remove_device(token)

    return r


# ---------- Приложение ----------

def create_app(service: PriceService | None = None, db_path: str | None = None,
               apple: AppleTokenVerifier | None = None, push: PushSender | None = None) -> FastAPI:
    holder: dict[str, Any] = {}

    db = open_db(db_path or os.getenv("COMMUNITY_DB", "community.db"))
    community = CommunityStore(db)  # создаёт таблицу blocks, на которую ссылаются уведомления
    s = Stores(
        auth=AuthStore(db),
        community=community,
        notifications=NotificationStore(db),
        apple=apple or AppleTokenVerifier(audience=os.getenv("APPLE_BUNDLE_ID", "com.garybail.recipeapp")),
        push=push or push_from_env(),
    )

    @asynccontextmanager
    async def lifespan(_: FastAPI):
        holder["service"] = service or PriceService(default_adapters())
        yield
        await holder["service"].close()
        db.close()

    app = FastAPI(title="Recipe app", lifespan=lifespan)
    app.state.stores = s

    def token_dep(authorization: str | None = Header(default=None)) -> str:
        token = _bearer(authorization)
        if token is None:
            raise HTTPException(401, "Нужно войти в аккаунт")
        return token

    def current_user(token: str = Depends(token_dep)) -> dict:
        user = s.auth.user_for_token(token)
        if user is None:
            raise HTTPException(401, "Сессия истекла, войдите снова")
        return user

    def optional_user(authorization: str | None = Header(default=None)) -> dict | None:
        token = _bearer(authorization)
        return s.auth.user_for_token(token) if token else None

    app.include_router(auth_router(s, current_user, token_dep))
    app.include_router(community_router(s, current_user, optional_user))
    app.include_router(notifications_router(s, current_user))

    def svc() -> PriceService:
        return holder["service"]

    def city_or_404(city_id: str):
        city = svc().city(city_id)
        if city is None:
            raise HTTPException(404, f"Неизвестный город: {city_id}")
        return city

    @app.get("/health")
    async def health():
        return {"ok": True}

    @app.get("/cities")
    async def cities():
        return [{"id": c.id, "name": c.name} for c in CITIES]

    @app.get("/stores")
    async def stores(city: str):
        adapters = await svc().stores_for(city_or_404(city))
        return [
            {
                "id": a.info.id,
                "name": a.info.name,
                "delivery_fee": str(a.info.delivery_fee),
                "free_delivery_from": str(a.info.free_delivery_from) if a.info.free_delivery_from is not None else None,
                "min_order": str(a.info.min_order),
                "delivery_note": a.info.delivery_note,
                "app_scheme": a.info.app_scheme,
                "app_store_url": a.info.app_store_url,
                "web_url": a.info.web_url,
            }
            for a in adapters
        ]

    @app.get("/search")
    async def search(store: str, city: str, q: str):
        if store not in svc().adapters:
            raise HTTPException(404, f"Неизвестный магазин: {store}")
        offers = await svc().search(store, city_or_404(city), q)
        return [o.to_json() for o in offers]

    @app.post("/offers")
    async def offers(body: OffersIn):
        if body.store not in svc().adapters:
            raise HTTPException(404, f"Неизвестный магазин: {body.store}")
        lines = [CartLineRequest(**l.model_dump()) for l in body.lines]
        matches = await svc().match_lines(body.store, city_or_404(body.city), lines)
        return {"offers": {pid: m.to_json() for pid, m in matches.items()}}

    return app


app = create_app()
