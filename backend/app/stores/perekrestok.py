"""Перекрёсток через библиотеку perekrestok-api (неофициальная, MIT, Open-Inflation)."""

from __future__ import annotations

import asyncio
import logging
from decimal import Decimal
from typing import Any

from ..models import City, Offer, StoreInfo
from ..units import parse_size

log = logging.getLogger(__name__)

STORE_ID = "perekrestok"

INFO = StoreInfo(
    id=STORE_ID,
    name="Перекрёсток",
    web_url="https://www.perekrestok.ru",
)


def _kopecks(value: Any) -> Decimal | None:
    if value is None:
        return None
    return (Decimal(int(value)) / 100).quantize(Decimal("0.01"))


def parse_search(payload: dict[str, Any]) -> list[Offer]:
    """Ответ /catalog/search/all -> список предложений. Цены у Перекрёстка в копейках."""
    content = payload.get("content") or {}
    offers: list[Offer] = []
    for p in content.get("products") or []:
        tag = p.get("priceTag") or {}
        price = _kopecks(tag.get("price"))
        if price is None:
            continue
        md = p.get("masterData") or {}
        title = p.get("title") or ""
        unit_name = (md.get("unitName") or "").lower()

        if unit_name == "кг":
            amount, unit, weighted = 1000.0, "g", True
        else:
            weighted = False
            size = parse_size(title)
            if size:
                amount, unit = size
            else:
                amount, unit = 1.0, "pcs"

        offers.append(Offer(
            store_id=STORE_ID,
            sku=str(md.get("plu") or p.get("id")),
            title=title,
            price=price,
            package_amount=amount,
            unit=unit,
            in_stock=(p.get("balanceState") or "many") != "none",
            is_weighted=weighted,
            regular_price=_kopecks(tag.get("grossPrice")),
        ))
    return offers


class PerekrestokAdapter:
    """Держит одну браузерную сессию; запросы идут по очереди."""

    info = INFO

    def __init__(self, headless: bool | str = True):
        self._headless = headless
        self._api: Any = None
        self._city_id: str | None = None
        self._lock = asyncio.Lock()

    async def _ensure(self) -> Any:
        if self._api is None:
            from perekrestok_api import PerekrestokAPI  # тяжёлый импорт (браузер)

            api = PerekrestokAPI(headless=self._headless)
            await api.__aenter__()
            self._api = api
        return self._api

    async def _select_city(self, api: Any, city: City) -> None:
        if self._city_id == city.id:
            return
        from perekrestok_api import abstraction

        position = abstraction.Geoposition(latitude=city.latitude, longitude=city.longitude)
        await api.Geolocation.Selection.delivery_point(position)
        self._city_id = city.id

    async def delivers_to(self, city: City) -> bool:
        async with self._lock:
            api = await self._ensure()
            resp = await api.Geolocation.search(city.name, limit=5)
            items = (resp.json().get("content") or {}).get("items") or []
            return any(i.get("name") == city.name and i.get("isDeliveryAvailable") for i in items)

    async def search(self, city: City, query: str) -> list[Offer]:
        async with self._lock:
            api = await self._ensure()
            await self._select_city(api, city)
            resp = await api.Catalog.search(query, entity_types=["product"])
            return parse_search(resp.json())

    async def close(self) -> None:
        if self._api is not None:
            await self._api.close()
            self._api = None
