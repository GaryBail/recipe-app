"""HTTP API для iOS-приложения.

Запуск: uvicorn app.main:app --host 0.0.0.0 --port 8000
"""

from __future__ import annotations

import os
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

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


def default_adapters() -> list[StoreAdapter]:
    from .stores.perekrestok import PerekrestokAdapter
    from .stores.pyaterochka import PyaterochkaAdapter

    headless = os.getenv("HEADLESS", "1") != "0"
    return [PerekrestokAdapter(headless=headless), PyaterochkaAdapter(headless=headless)]


def create_app(service: PriceService | None = None) -> FastAPI:
    holder: dict[str, PriceService] = {}

    @asynccontextmanager
    async def lifespan(_: FastAPI):
        holder["service"] = service or PriceService(default_adapters())
        yield
        await holder["service"].close()

    app = FastAPI(title="Recipe app prices", lifespan=lifespan)

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
