"""HTTP API для iOS-приложения: цены, аккаунты, сообщество, уведомления.

Запуск: uvicorn app.main:app --host 0.0.0.0 --port 8000
"""

from __future__ import annotations

import asyncio
import logging
import os
from contextlib import asynccontextmanager
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any

from fastapi import APIRouter, BackgroundTasks, Depends, FastAPI, Header, HTTPException, Request
from pydantic import BaseModel, Field

from .auth import (AppleLoginIn, AppleTokenError, AppleTokenVerifier, AuthStore, ChangePasswordIn, CodeIn,
                   CodeTooSoon, EmailTaken, ForgotIn, LoginIn, ProfileUpdateIn, RegisterIn, ResetIn)
from .mailer import Mailer, code_email, mailer_from_env
from .ratelimit import RateLimiter, wait_text
from .community import BlockIn, CommunityStore, PublishIn, RatingIn, ReportIn, open_db
from .models import CartLineRequest
from .notifications import APNsPush, DeviceIn, MarkReadIn, NoopPush, NotificationStore, PushSender, describe
from .recipes_social import (RECIPE_ID_RE, UPLOADS_PER_DAY, BadImage, PhotoReportIn,
                             RecipeSocialStore)
from .price_watch import (WATCH_CITIES, PriceWatcher, TooManyWatches, WatchIn, WatchStore, hours_from_env,
                          scheduler_loop)
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
    mailer: Mailer
    limiter: RateLimiter
    watches: Any = None
    recipes: Any = None


# Лимиты: (сколько, за сколько секунд)
LOGIN_PER_EMAIL = (5, 15 * 60)
LOGIN_PER_IP = (20, 15 * 60)
REGISTER_PER_IP = (10, 3600)
CODES_PER_EMAIL = (5, 3600)
CODES_PER_IP = (20, 3600)
RESET_ATTEMPTS_PER_EMAIL = (10, 3600)


def client_ip(request: Request) -> str:
    # За обратным прокси (nginx и т.п.) реальный адрес приходит в X-Forwarded-For.
    if os.getenv("TRUST_PROXY") == "1":
        forwarded = request.headers.get("x-forwarded-for")
        if forwarded:
            return forwarded.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


def limit(s: Stores, key: str, rule: tuple[int, int]) -> None:
    wait = s.limiter.retry_after(key, *rule)
    if wait:
        raise HTTPException(429, wait_text(wait), headers={"Retry-After": str(wait)})


def default_adapters() -> list[StoreAdapter]:
    from .stores.perekrestok import PerekrestokAdapter
    from .stores.pyaterochka import PyaterochkaAdapter

    return [PerekrestokAdapter(headless=headless_mode()), PyaterochkaAdapter(headless=headless_mode())]


def headless_mode(raw: str | None = None) -> bool | str:
    """HEADLESS: 1 — скрытый браузер, 0 — окно (для отладки), virtual — виртуальный экран Xvfb (на сервере)."""
    raw = (raw if raw is not None else os.getenv("HEADLESS", "1")).strip().lower()
    if raw == "virtual":
        return "virtual"
    return raw != "0"


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

    async def send_code(user_id: str, email: str, name: str, purpose: str, background: BackgroundTasks) -> None:
        code = s.auth.create_code(user_id, purpose)
        subject, text = code_email(purpose, code, name)
        background.add_task(s.mailer.send, email, subject, text)

    @r.post("/register", status_code=201)
    async def register(body: RegisterIn, request: Request, background: BackgroundTasks):
        ip_key = f"register:ip:{client_ip(request)}"
        limit(s, ip_key, REGISTER_PER_IP)
        s.limiter.hit(ip_key)
        try:
            user, token = s.auth.register(body)
        except EmailTaken:
            raise HTTPException(409, "Этот email уже зарегистрирован")
        await send_code(user["id"], user["email"], user["display_name"], "verify", background)
        return session(user, token, created=True)

    @r.post("/login")
    async def login(body: LoginIn, request: Request):
        email_key = f"login:email:{body.email.strip().lower()}"
        ip_key = f"login:ip:{client_ip(request)}"
        limit(s, email_key, LOGIN_PER_EMAIL)
        limit(s, ip_key, LOGIN_PER_IP)
        result = await asyncio.to_thread(s.auth.login, body.email, body.password)
        if result is None:
            s.limiter.hit(email_key)
            s.limiter.hit(ip_key)
            raise HTTPException(401, "Неверный email или пароль")
        s.limiter.clear(email_key)
        return session(*result)

    @r.post("/verify-email/send", status_code=204)
    async def resend_verification(request: Request, background: BackgroundTasks,
                                  user: dict = Depends(current_user)):
        if user["email_verified"]:
            raise HTTPException(409, "Email уже подтверждён")
        if not user["email"]:
            raise HTTPException(422, "У аккаунта нет email")
        limit(s, f"codes:ip:{client_ip(request)}", CODES_PER_IP)
        s.limiter.hit(f"codes:ip:{client_ip(request)}")
        try:
            await send_code(user["id"], user["email"], user["display_name"], "verify", background)
        except CodeTooSoon as e:
            raise HTTPException(429, f"Новый код можно запросить через {e.retry_after} с",
                                headers={"Retry-After": str(e.retry_after)})

    @r.post("/verify-email")
    async def verify_email(body: CodeIn, user: dict = Depends(current_user)):
        if user["email_verified"]:
            return user
        if not s.auth.check_code(user["id"], "verify", body.code):
            raise HTTPException(400, "Неверный или просроченный код")
        return s.auth.mark_email_verified(user["id"])

    @r.post("/password/forgot", status_code=204)
    async def forgot_password(body: ForgotIn, request: Request, background: BackgroundTasks):
        """Всегда отвечает одинаково, чтобы нельзя было узнать, зарегистрирован ли email."""
        email = body.email.strip().lower()
        ip_key = f"codes:ip:{client_ip(request)}"
        limit(s, ip_key, CODES_PER_IP)
        s.limiter.hit(ip_key)
        email_key = f"codes:email:{email}"
        if s.limiter.retry_after(email_key, *CODES_PER_EMAIL):
            return
        s.limiter.hit(email_key)
        row = s.auth.user_row_by_email(email)
        if row is None or row["password_hash"] is None:
            return
        try:
            await send_code(row["id"], row["email"], row["display_name"], "reset", background)
        except CodeTooSoon:
            return

    @r.post("/password/reset")
    async def reset_password(body: ResetIn):
        email = body.email.strip().lower()
        key = f"reset:email:{email}"
        limit(s, key, RESET_ATTEMPTS_PER_EMAIL)
        s.limiter.hit(key)
        row = s.auth.user_row_by_email(email)
        if row is None or not s.auth.check_code(row["id"], "reset", body.code):
            raise HTTPException(400, "Неверный или просроченный код")
        token = s.auth.set_password(row["id"], body.new_password)
        user = s.auth.mark_email_verified(row["id"])  # код с почты подтверждает владение email
        s.limiter.clear(f"login:email:{email}")
        return session(user, token)

    @r.post("/password/change")
    async def change_password(body: ChangePasswordIn, user: dict = Depends(current_user)):
        key = f"change:user:{user['id']}"
        limit(s, key, LOGIN_PER_EMAIL)
        if not s.auth.verify_user_password(user["id"], body.old_password):
            s.limiter.hit(key)
            raise HTTPException(400, "Текущий пароль указан неверно")
        token = s.auth.set_password(user["id"], body.new_password)
        return session(s.auth.public(s.auth.raw_user(user["id"])), token)

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
        if s.watches is not None:
            s.watches.delete_user(user["id"])
        if s.recipes is not None:
            s.recipes.delete_user(user["id"])
        s.auth.delete(user["id"])

    return r


# ---------- Сообщество ----------

def community_router(s: Stores, current_user, optional_user) -> APIRouter:
    r = APIRouter(prefix="/community", tags=["community"])

    def verified_user(user: dict = Depends(current_user)) -> dict:
        if not user["email_verified"]:
            raise HTTPException(403, "Подтвердите email, чтобы публиковать сборки и ставить оценки")
        return user

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
    async def publish(body: PublishIn, user: dict = Depends(verified_user)):
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
                   user: dict = Depends(verified_user)):
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


# ---------- Рецепты: лайки, популярное, фото ----------

class CoversIn(BaseModel):
    ids: list[str] = Field(max_length=200)


def recipes_router(s: Stores, current_user, optional_user) -> APIRouter:
    r = APIRouter(tags=["recipes"])

    def check_id(recipe_id: str) -> str:
        if not RECIPE_ID_RE.match(recipe_id):
            raise HTTPException(422, "Некорректный id рецепта")
        return recipe_id

    def me(user: dict | None) -> str:
        return user["id"] if user else ""

    @r.get("/recipes/popular")
    async def popular(limit: int = 10, user: dict | None = Depends(optional_user)):
        return s.recipes.popular(me(user), limit=max(1, min(limit, 30)))

    @r.post("/recipes/covers")
    async def covers(body: CoversIn, user: dict | None = Depends(optional_user)):
        return s.recipes.covers([i for i in body.ids if RECIPE_ID_RE.match(i)], me(user))

    @r.get("/recipes/{recipe_id}")
    async def summary(recipe_id: str, user: dict | None = Depends(optional_user)):
        return s.recipes.summary(check_id(recipe_id), me(user))

    @r.put("/recipes/{recipe_id}/like", status_code=204)
    async def like(recipe_id: str, user: dict = Depends(current_user)):
        s.recipes.like(check_id(recipe_id), user["id"])

    @r.delete("/recipes/{recipe_id}/like", status_code=204)
    async def unlike(recipe_id: str, user: dict = Depends(current_user)):
        s.recipes.unlike(check_id(recipe_id), user["id"])

    @r.get("/me/likes")
    async def my_likes(user: dict = Depends(current_user)):
        return s.recipes.liked_ids(user["id"])

    @r.post("/recipes/{recipe_id}/photos", status_code=201)
    async def upload_photo(recipe_id: str, request: Request, user: dict = Depends(current_user)):
        """Тело запроса — сам файл (image/jpeg, image/png или image/webp), до 10 МБ."""
        check_id(recipe_id)
        if not user["email_verified"]:
            raise HTTPException(403, "Подтвердите email, чтобы загружать фото")
        key = f"photos:user:{user['id']}"
        limit(s, key, UPLOADS_PER_DAY)
        declared = int(request.headers.get("content-length") or 0)
        if declared > 10 * 1024 * 1024:
            raise HTTPException(413, "Фото больше 10 МБ")
        data = await request.body()
        try:
            photo = await asyncio.to_thread(s.recipes.add_photo, recipe_id, user["id"], user["display_name"], data)
        except BadImage as e:
            raise HTTPException(422, str(e))
        s.limiter.hit(key)
        return photo

    @r.delete("/photos/{photo_id}", status_code=204)
    async def delete_photo(photo_id: str, user: dict = Depends(current_user)):
        if not s.recipes.delete_photo(photo_id, user["id"]):
            raise HTTPException(404, "Фото не найдено или загружено другим пользователем")

    @r.post("/photos/{photo_id}/report", status_code=204)
    async def report_photo(photo_id: str, body: PhotoReportIn, user: dict = Depends(current_user)):
        if not s.recipes.photo_exists(photo_id):
            raise HTTPException(404, "Фото не найдено")
        s.recipes.report_photo(photo_id, user["id"], body.reason)

    return r


# ---------- Слежение за ценами ----------

def watches_router(s: Stores, current_user) -> APIRouter:
    r = APIRouter(prefix="/watches", tags=["price watch"])

    @r.get("")
    async def list_watches(user: dict = Depends(current_user)):
        return s.watches.list(user["id"])

    @r.put("/{client_id}")
    async def upsert_watch(client_id: str, body: WatchIn, user: dict = Depends(current_user)):
        if body.city_id not in WATCH_CITIES:
            raise HTTPException(422, "Слежение за ценами пока работает только для Москвы")
        if len(client_id) > 64:
            raise HTTPException(422, "Слишком длинный id")
        try:
            return s.watches.upsert(user["id"], client_id, body, datetime.now(timezone.utc))
        except TooManyWatches:
            raise HTTPException(409, "Можно следить не больше чем за 20 сборками")

    @r.get("/{client_id}")
    async def get_watch(client_id: str, user: dict = Depends(current_user)):
        watch = s.watches.get(user["id"], client_id)
        if watch is None:
            raise HTTPException(404, "Подписка не найдена")
        return watch

    @r.delete("/{client_id}", status_code=204)
    async def delete_watch(client_id: str, user: dict = Depends(current_user)):
        s.watches.delete(user["id"], client_id)

    return r


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
               apple: AppleTokenVerifier | None = None, push: PushSender | None = None,
               mailer: Mailer | None = None, limiter_clock=None, price_watch: bool | None = None,
               media_dir: str | None = None) -> FastAPI:
    holder: dict[str, Any] = {}

    db = open_db(db_path or os.getenv("COMMUNITY_DB", "community.db"))
    community = CommunityStore(db)  # создаёт таблицу blocks, на которую ссылаются уведомления
    s = Stores(
        auth=AuthStore(db),
        community=community,
        notifications=NotificationStore(db),
        apple=apple or AppleTokenVerifier(audience=os.getenv("APPLE_BUNDLE_ID", "com.garybail.recipeapp")),
        push=push or push_from_env(),
        mailer=mailer or mailer_from_env(),
        limiter=RateLimiter(db, clock=limiter_clock) if limiter_clock else RateLimiter(db),
    )

    s.watches = WatchStore(db)
    media_dir = media_dir or os.getenv("MEDIA_DIR", "media")
    s.recipes = RecipeSocialStore(db, media_dir)
    watch_enabled = price_watch if price_watch is not None else os.getenv("PRICE_WATCH", "1") != "0"

    @asynccontextmanager
    async def lifespan(app_: FastAPI):
        holder["service"] = service or PriceService(default_adapters())
        watcher = PriceWatcher(s.watches, holder["service"], s.notifications, s.auth, s.push)
        app_.state.watcher = watcher
        task = None
        if watch_enabled:
            task = asyncio.create_task(scheduler_loop(watcher, hours_from_env(os.getenv("PRICE_REFRESH_HOURS"))))
        yield
        if task:
            task.cancel()
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
    app.include_router(watches_router(s, current_user))
    app.include_router(recipes_router(s, current_user, optional_user))
    # Фото рецептов. Имена файлов — случайные id, папка содержит только пережатые картинки.
    from fastapi.staticfiles import StaticFiles
    app.mount("/media", StaticFiles(directory=media_dir), name="media")

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
        try:
            offers = await svc().search(store, city_or_404(city), q)
        except HTTPException:
            raise
        except Exception as e:
            log.warning("search failed: %s %r: %s", store, q, e)
            raise HTTPException(502, "Магазин сейчас не отвечает, попробуйте позже")
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
