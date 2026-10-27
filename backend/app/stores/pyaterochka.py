"""Пятёрочка через библиотеку pyaterochka-api (неофициальная, MIT, Open-Inflation)."""

from __future__ import annotations

import asyncio
import logging
from decimal import Decimal
from typing import Any

from ..models import City, Offer, StoreInfo
from ..units import parse_size

log = logging.getLogger(__name__)

STORE_ID = "pyaterochka"

INFO = StoreInfo(
    id=STORE_ID,
    name="Пятёрочка",
    web_url="https://5ka.ru",
)


def _rub(value: Any) -> Decimal | None:
    if value in (None, ""):
        return None
    return Decimal(str(value)).quantize(Decimal("0.01"))


def parse_products(payload: dict[str, Any]) -> list[Offer]:
    """Ответ поиска / списка товаров -> предложения. Цены у Пятёрочки в рублях строкой."""
    offers: list[Offer] = []
    for p in payload.get("products") or []:
        prices = p.get("prices") or {}
        regular = _rub(prices.get("regular"))
        discount = _rub(prices.get("discount"))
        price = discount or regular
        if price is None:
            continue

        name = p.get("name") or ""
        uom = (p.get("uom") or "").lower()
        if uom == "кг":
            amount, unit, weighted = 1000.0, "g", True
        else:
            weighted = False
            size = parse_size(p.get("property_clarification")) or parse_size(name)
            if size:
                amount, unit = size
            else:
                amount, unit = 1.0, "pcs"

        images = (p.get("image_links") or {}).get("small") or []
        offers.append(Offer(
            store_id=STORE_ID,
            sku=str(p.get("plu")),
            title=name,
            price=price,
            package_amount=amount,
            unit=unit,
            in_stock=bool(p.get("is_available", True)),
            is_weighted=weighted,
            regular_price=regular if discount else None,
            image_url=images[0] if images else None,
        ))
    return offers


class PyaterochkaAdapter:
    """Ищет ближайший магазин доставки для города и ищет товары в нём."""

    info = INFO

    def __init__(self, headless: bool | str = True):
        self._headless = headless
        self._api: Any = None
        self._stores: dict[str, dict[str, Any]] = {}  # city.id -> ответ find_store
        self._lock = asyncio.Lock()

    async def _ensure(self) -> Any:
        if self._api is None:
            from pyaterochka_api import PyaterochkaAPI  # тяжёлый импорт (браузер)

            api = PyaterochkaAPI(headless=self._headless)
            await api.__aenter__()
            self._api = api
        return self._api

    async def _store_for(self, api: Any, city: City) -> dict[str, Any]:
        if city.id not in self._stores:
            resp = await api.Geolocation.find_store(longitude=city.longitude, latitude=city.latitude)
            self._stores[city.id] = resp.json() or {}
        return self._stores[city.id]

    async def delivers_to(self, city: City) -> bool:
        async with self._lock:
            api = await self._ensure()
            store = await self._store_for(api, city)
            return bool(store.get("sap_code")) and bool(store.get("has_delivery"))

    async def search(self, city: City, query: str) -> list[Offer]:
        from pyaterochka_api import PurchaseMode

        async with self._lock:
            api = await self._ensure()
            store = await self._store_for(api, city)
            sap = store.get("sap_code")
            if not sap:
                return []
            resp = await api.Catalog.search(sap, query, mode=PurchaseMode.DELIVERY, limit=20)
            return parse_products(resp.json())

    async def close(self) -> None:
        if self._api is not None:
            await self._api.close()
            self._api = None
