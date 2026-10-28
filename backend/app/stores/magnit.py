"""Магнит через API мобильного приложения (middle-api.magnit.ru). Неофициально.

Поиск и список магазинов работают без входа в аккаунт. Каталог — «экспресс-доставка» из
магазина у дома (storeType=express, catalogType=2): цены конкретного магазина, в копейках.
Магазин выбираем ближайший к центру города среди тех, что доставляют.
Запросы описаны по открытому клиенту ecomkit (MIT): github.com/The-Fisher-Slopworks-Co/ecomkit.
"""

from __future__ import annotations

import asyncio
import logging
import uuid
from decimal import Decimal
from typing import Any

from ..models import City, Offer, StoreInfo
from ..units import parse_size
from .base import StoreUnavailable
from .geo import distance_m

log = logging.getLogger(__name__)

STORE_ID = "magnit"
API_URL = "https://middle-api.magnit.ru/"
EXPRESS = {"storeType": "express", "catalogType": "2"}
SEARCH_RADIUS_M = 3000
APP_HEADERS = {
    "user-agent": "Dalvik/2.1.0 (Linux; U; Android 14; SM-S918B Build/UP1A.231005.007)",
    "x-app-version": "8.124.0",
    "x-device-platform": "Android",
    "x-platform-version": "36",
}

INFO = StoreInfo(id=STORE_ID, name="Магнит", web_url="https://magnit.ru")


def _rub(kopecks: Any) -> Decimal:
    return (Decimal(int(kopecks)) / 100).quantize(Decimal("0.01"))


def nearest_store(payload: dict[str, Any], city: City) -> str | None:
    """Ответ v1/stores-facade/search → код ближайшего к центру магазина «Магнит»."""
    items = ((payload.get("items") or {}).get("items")) or []
    best: tuple[float, str] | None = None
    for s in items:
        ext = s.get("externalId") or {}
        coords = s.get("coordinates") or {}
        if ext.get("owner") != "OWNER_MAGNIT" or not s.get("isActive", True) or "latitude" not in coords:
            continue
        d = distance_m(city.latitude, city.longitude, coords["latitude"], coords["longitude"])
        if best is None or d < best[0]:
            best = (d, str(ext["storeCode"]))
    return best[1] if best else None


def parse_goods(payload: dict[str, Any]) -> list[Offer]:
    """Ответ v2/goods/search → предложения.

    Весовой товар продаётся порциями фиксированного веса (`weighted.step`, например пакет картофеля 2 кг),
    `price` — цена порции. Считаем порцию упаковкой.
    """
    offers: list[Offer] = []
    for good in payload.get("items") or []:
        if good.get("id") is None or good.get("price") is None:
            continue
        title = " ".join(str(good.get("name") or "").split())
        price = _rub(good["price"])
        weighted = good.get("weighted") or {}
        if weighted.get("isWeighted") and weighted.get("step"):
            amount, unit = float(weighted["step"]), "g"
        else:
            size = parse_size(title)
            amount, unit = size if size else (1.0, "pcs")
        old = (good.get("promotion") or {}).get("oldPrice")
        regular = _rub(old) if old else None
        gallery = good.get("gallery") or []
        offers.append(Offer(
            store_id=STORE_ID,
            sku=str(good["id"]),
            title=title,
            price=price,
            package_amount=amount,
            unit=unit,
            in_stock=(good.get("quantity") or 0) > 0 and not good.get("isMissing"),
            regular_price=regular if regular is not None and regular > price else None,
            image_url=gallery[0].get("url") if gallery else None,
        ))
    return offers


class MagnitAdapter:
    info = INFO

    def __init__(self, client: Any = None, base_url: str = API_URL):
        self._client = client
        self._base_url = base_url
        self._store_for_city: dict[str, str | None] = {}
        self._lock = asyncio.Lock()

    async def _http(self) -> Any:
        if self._client is None:
            import httpx
            self._client = httpx.AsyncClient(base_url=self._base_url, timeout=25,
                                             headers={**APP_HEADERS, "x-device-id": str(uuid.uuid4())})
        return self._client

    async def _post(self, path: str, body: dict[str, Any]) -> Any:
        client = await self._http()
        try:
            resp = await client.post(path, json=body)
        except Exception as e:  # сеть, таймаут
            raise StoreUnavailable(f"Магнит: {e}") from e
        if resp.status_code >= 400:
            raise StoreUnavailable(f"Магнит: HTTP {resp.status_code}")
        return resp.json()

    async def store_for(self, city: City) -> str | None:
        async with self._lock:
            if city.id not in self._store_for_city:
                payload = await self._post("v1/stores-facade/search", {"filters": {
                    "geo": {"typeName": "circle", "distance_meters": SEARCH_RADIUS_M,
                            "coordinates": {"latitude": city.latitude, "longitude": city.longitude}},
                    "deliveryTypeList": ["DELIVERY_TYPE_DELIVERY"]}})
                self._store_for_city[city.id] = nearest_store(payload, city)
                log.info("Магнит %s: магазин %s", city.id, self._store_for_city[city.id])
            return self._store_for_city[city.id]

    async def delivers_to(self, city: City) -> bool:
        return await self.store_for(city) is not None

    async def search(self, city: City, query: str) -> list[Offer]:
        store = await self.store_for(city)
        if store is None:
            return []
        payload = await self._post("v2/goods/search", {
            **EXPRESS, "storeCode": store, "term": query[:200],
            "pagination": {"limit": 20, "offset": 0}, "sort": {"order": "desc", "type": "relevance"}})
        return parse_goods(payload)

    async def close(self) -> None:
        if self._client is not None:
            await self._client.aclose()
            self._client = None
