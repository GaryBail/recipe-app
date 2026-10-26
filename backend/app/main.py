"""HTTP API для iOS-приложения.

Запуск: uvicorn app.main:app --host 0.0.0.0 --port 8000
"""

from __future__ import annotations

import os
from contextlib import asynccontextmanager

import re

from fastapi import APIRouter, FastAPI, Header, HTTPException
from pydantic import BaseModel, Field

from .community import BlockIn, CommunityStore, PublishIn, RatingIn, ReportIn
from .models import CartLineRequest
from .service import CITIES, PriceService
from .stores.base import StoreAdapter


class LineIn(BaseModel):
    product_id: str
    query: str = Field(min_length=2)
    required_amount: float = Field(gt=0)
    unit: str = Field(pattern="^(g|ml|pcs)$")


class OffersIn(BaseModel):
    store: str
    city: str
    lines: list[LineIn]


_USER_ID_RE = re.compile(r"^[0-9a-fA-F-]{32,36}$")


def _user(x_user_id: str | None) -> str:
    """Анонимный идентификатор устройства. Для App Store заменить на Sign in with Apple."""
    if not x_user_id or not _USER_ID_RE.match(x_user_id):
        raise HTTPException(401, "Нужен заголовок X-User-Id (UUID устройства)")
    return x_user_id.lower()


def community_router(store: CommunityStore) -> APIRouter:
    r = APIRouter(prefix="/community", tags=["community"])

    def found(build_id: str, user: str) -> dict:
        build = store.get(build_id, user)
        if build is None:
            raise HTTPException(404, "Сборка не найдена")
        return build

    @r.get("/builds")
    async def list_builds(recipe_id: str | None = None, sort: str = "top", mine: bool = False,
                          limit: int = 50, x_user_id: str | None = Header(default=None)):
        if sort not in ("top", "new"):
            raise HTTPException(422, "sort: top | new")
        return store.list(_user(x_user_id), recipe_id=recipe_id, sort=sort, mine=mine,
                          limit=max(1, min(limit, 100)))

    @r.post("/builds", status_code=201)
    async def publish(body: PublishIn, x_user_id: str | None = Header(default=None)):
        return store.publish(_user(x_user_id), body)

    @r.get("/builds/{build_id}")
    async def get_build(build_id: str, x_user_id: str | None = Header(default=None)):
        return found(build_id, _user(x_user_id))

    @r.delete("/builds/{build_id}", status_code=204)
    async def delete_build(build_id: str, x_user_id: str | None = Header(default=None)):
        if not store.delete(build_id, _user(x_user_id)):
            raise HTTPException(404, "Сборка не найдена или принадлежит другому пользователю")

    @r.get("/builds/{build_id}/ratings")
    async def ratings(build_id: str, x_user_id: str | None = Header(default=None)):
        user = _user(x_user_id)
        found(build_id, user)
        return store.ratings(build_id, user)

    @r.put("/builds/{build_id}/rating")
    async def rate(build_id: str, body: RatingIn, x_user_id: str | None = Header(default=None)):
        user = _user(x_user_id)
        build = found(build_id, user)
        if build["author_id"] == user:
            raise HTTPException(403, "Нельзя оценивать свою сборку")
        store.rate(build_id, user, body)
        return found(build_id, user)

    @r.post("/builds/{build_id}/report", status_code=204)
    async def report(build_id: str, body: ReportIn, x_user_id: str | None = Header(default=None)):
        user = _user(x_user_id)
        found(build_id, user)
        store.report(build_id, user, body.reason)

    @r.post("/blocks", status_code=204)
    async def block(body: BlockIn, x_user_id: str | None = Header(default=None)):
        user = _user(x_user_id)
        if body.user_id.lower() == user:
            raise HTTPException(422, "Нельзя заблокировать себя")
        store.block(user, body.user_id.lower())

    return r


def default_adapters() -> list[StoreAdapter]:
    from .stores.perekrestok import PerekrestokAdapter
    from .stores.pyaterochka import PyaterochkaAdapter

    headless = os.getenv("HEADLESS", "1") != "0"
    return [PerekrestokAdapter(headless=headless), PyaterochkaAdapter(headless=headless)]


def create_app(service: PriceService | None = None, community: CommunityStore | None = None) -> FastAPI:
    holder: dict[str, PriceService] = {}

    @asynccontextmanager
    async def lifespan(_: FastAPI):
        holder["service"] = service or PriceService(default_adapters())
        yield
        await holder["service"].close()

    app = FastAPI(title="Recipe app", lifespan=lifespan)
    store = community or CommunityStore(os.getenv("COMMUNITY_DB", "community.db"))
    app.include_router(community_router(store))

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
