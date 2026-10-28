"""Ашан через API сайта auchan.ru (тот же, что вызывает сам сайт). Неофициально.

- GET  /v1/shops?merchantId=1         — магазины с координатами и условиями доставки;
- POST /v1/search?merchantId=<магазин> {"query": "..."} — поиск с ценами и остатками магазина.
Цены в рублях. Единица цены: per=item (за штуку), weight_kg (за кг), weight_100g (за 100 г).
"""

from __future__ import annotations

import asyncio
import logging
from decimal import Decimal
from typing import Any

from ..models import City, Offer, StoreInfo
from ..units import parse_size
from .base import StoreUnavailable
from .geo import distance_m

log = logging.getLogger(__name__)

STORE_ID = "auchan"
SITE = "https://www.auchan.ru"
MAX_DISTANCE_M = 40_000
MAX_RESULTS = 20
HEADERS = {
    "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148",
    "Accept": "application/json",
    "Referer": f"{SITE}/",
    "Origin": SITE,
}

INFO = StoreInfo(id=STORE_ID, name="Ашан", web_url=SITE)


def _money(value: Any) -> Decimal:
    return Decimal(str(value)).quantize(Decimal("0.01"))


def pick_shop(shops: list[dict[str, Any]], city: City) -> dict[str, Any] | None:
    """Ближайший к центру города магазин с доставкой."""
    best: tuple[float, dict[str, Any]] | None = None
    for s in shops:
        if not s.get("geo_lat") or not s.get("geo_lon") or s.get("is_visible") is False:
            continue
        if not (s.get("delivery") or s.get("express_delivery")):
            continue
        d = distance_m(city.latitude, city.longitude, float(s["geo_lat"]), float(s["geo_lon"]))
        if d <= MAX_DISTANCE_M and (best is None or d < best[0]):
            best = (d, s)
    return best[1] if best else None


def parse_search(payload: dict[str, Any]) -> list[Offer]:
    offers: list[Offer] = []
    products = [p for group in payload.get("items") or [] for p in group.get("products") or []]
    for p in products[:MAX_RESULTS]:
        price = p.get("price") or {}
        if p.get("id") is None or price.get("value") is None:
            continue
        title = " ".join(str(p.get("name") or "").split())
        per = price.get("per") or "item"
        factor = {"weight_kg": 1, "weight_100g": 10}.get(per)
        old = (p.get("oldPrice") or {}).get("value")
        if factor:  # весовой: приводим к цене за килограмм
            value, regular = _money(price["value"]) * factor, _money(old) * factor if old else None
            amount, unit, weighted = 1000.0, "g", True
        else:
            value, regular = _money(price["value"]), _money(old) if old else None
            # в package_display бывают ошибки («10 кг» у десятка яиц) — название надёжнее
            size = parse_size(title) or parse_size(p.get("package_display"))
            amount, unit = size if size else (1.0, "pcs")
            weighted = False
        stock = p.get("stock") or {}
        offers.append(Offer(
            store_id=STORE_ID,
            sku=str(p["id"]),
            title=title,
            price=value,
            package_amount=amount,
            unit=unit,
            in_stock=bool(p.get("active", True)) and not stock.get("not_available") and (stock.get("qty") or 0) > 0,
            is_weighted=weighted,
            regular_price=regular if regular is not None and regular > value else None,
            image_url=p.get("imageUrl"),
        ))
    return offers


class AuchanAdapter:
    info = INFO

    def __init__(self, client: Any = None, base_url: str = SITE):
        self._client = client
        self._base_url = base_url
        self._shops: list[dict[str, Any]] | None = None
        self._shop_for_city: dict[str, int | None] = {}
        self._lock = asyncio.Lock()

    async def _http(self) -> Any:
        if self._client is None:
            import httpx
            self._client = httpx.AsyncClient(base_url=self._base_url, timeout=30, headers=HEADERS,
                                             follow_redirects=True)
        return self._client

    async def _request(self, method: str, path: str, **kw: Any) -> Any:
        client = await self._http()
        try:
            resp = await client.request(method, path, **kw)
        except Exception as e:  # сеть, таймаут
            raise StoreUnavailable(f"Ашан: {e}") from e
        if resp.status_code >= 400 or "json" not in resp.headers.get("content-type", ""):
            raise StoreUnavailable(f"Ашан: HTTP {resp.status_code}")
        return resp.json()

    async def shop_for(self, city: City) -> int | None:
        async with self._lock:
            if city.id not in self._shop_for_city:
                if self._shops is None:
                    self._shops = (await self._request("GET", "/v1/shops", params={"merchantId": 1})).get("shops") or []
                shop = pick_shop(self._shops, city)
                self._shop_for_city[city.id] = int(shop["merchant_id"]) if shop else None
                if shop:
                    log.info("Ашан %s: магазин %s (%s)", city.id, shop["merchant_id"], shop.get("name"))
            return self._shop_for_city[city.id]

    async def delivers_to(self, city: City) -> bool:
        return await self.shop_for(city) is not None

    async def search(self, city: City, query: str) -> list[Offer]:
        shop = await self.shop_for(city)
        if shop is None:
            return []
        payload = await self._request("POST", "/v1/search", params={"merchantId": shop},
                                      json={"query": query[:200]})  # постраничного вывода нет — отдаёт всё
        return parse_search(payload)

    async def close(self) -> None:
        if self._client is not None:
            await self._client.aclose()
            self._client = None
