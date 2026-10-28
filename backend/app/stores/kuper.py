"""Купер (бывший СберМаркет) — агрегатор доставки из разных сетей. Неофициально, API сайта web.kuper.ru.

- GET  /api/v3/mweb/shelves?lat=&lon= — какие магазины доставляют в точку (полка «shop»: id магазина и сеть);
- POST /api/web/v1/products {"q", "store_id"} — поиск по магазину с ценами Купера.

Купер защищён от ботов: нужен TLS-отпечаток браузера (curl_cffi, impersonate="chrome"), заголовки
referer/origin/x-requested-with и куки spid/spsc с главной страницы. Иногда вместо JSON приходит
JS-проверка — тогда магазин считается временно недоступным.

Цены в Купере обычно выше, чем у самой сети (наценка сервиса), зато один заказ и доставка Купера.
Какую сеть показывать как «Купер», задаёт KUPER_RETAILER (по умолчанию Лента — приоритетная сеть).
Способ запросов описан по открытому скрипту github.com/letsloose501/kuper-prices.
"""

from __future__ import annotations

import asyncio
import json
import logging
from decimal import Decimal
from typing import Any

from ..models import City, Offer, StoreInfo
from ..units import parse_size
from .base import StoreUnavailable

log = logging.getLogger(__name__)

STORE_ID = "kuper"
BASE = "https://web.kuper.ru"
HEADERS = {
    "accept": "application/json",
    "referer": f"{BASE}/",
    "origin": BASE,
    "x-requested-with": "XMLHttpRequest",
}
_VOLUME_UNITS = {"g": ("g", 1), "kg": ("g", 1000), "ml": ("ml", 1), "l": ("ml", 1000), "pcs": ("pcs", 1),
                 "piece": ("pcs", 1)}


def info_for(retailer: str) -> StoreInfo:
    return StoreInfo(id=STORE_ID, name=f"Купер · {retailer}", web_url="https://kuper.ru")


def stores_from_shelves(payload: dict[str, Any]) -> dict[str, str]:
    """Ответ mweb/shelves → {название сети в нижнем регистре: store_id}."""
    shop = ((payload.get("data") or {}).get("shelves_data") or {}).get("shop") or {}
    values = shop.values() if isinstance(shop, dict) else shop
    out: dict[str, str] = {}
    for s in values:
        name = ((s.get("retailer") or {}).get("name") or "").strip().lower()
        if name and s.get("id") is not None:
            out.setdefault(name, str(s["id"]))
    return out


def parse_products(payload: dict[str, Any]) -> list[Offer]:
    offers: list[Offer] = []
    for p in payload.get("products") or []:
        if p.get("id") is None or p.get("price") is None:
            continue
        title = " ".join(str(p.get("name") or "").split())
        price = Decimal(str(p["price"])).quantize(Decimal("0.01"))
        original = p.get("original_price")
        regular = Decimal(str(original)).quantize(Decimal("0.01")) if original else None
        if p.get("price_type") == "per_kilo":  # цена за килограмм, вес любой
            amount, unit, weighted = 1000.0, "g", True
        else:
            weighted = False
            # Название первым: у яиц «10 шт» в названии, а в volume — вес десятка
            size = parse_size(title)
            known = _VOLUME_UNITS.get(str(p.get("volume_type") or "").lower())
            if size:
                amount, unit = size
            elif known and p.get("volume"):
                our, k = known
                amount, unit = float(p["volume"]) * k * max(1, int(p.get("items_per_pack") or 1)), our
            else:
                amount, unit = parse_size(p.get("human_volume")) or (1.0, "pcs")
        images = p.get("image_urls") or []
        offers.append(Offer(
            store_id=STORE_ID,
            sku=str(p["id"]),
            title=title,
            price=price,
            package_amount=amount,
            unit=unit,
            in_stock=bool(p.get("available", True)),
            is_weighted=weighted,
            regular_price=regular if regular is not None and regular > price else None,
            image_url=images[0] if images else None,
        ))
    return offers


class KuperAdapter:
    def __init__(self, retailer: str = "Лента", session: Any = None):
        self.retailer = retailer
        self.info = info_for(retailer)
        self._session = session
        self._store_for_city: dict[str, str | None] = {}
        self._lock = asyncio.Lock()

    async def _http(self, fresh: bool = False) -> Any:
        if self._session is None or fresh:
            from curl_cffi.requests import AsyncSession
            session = AsyncSession(impersonate="chrome", timeout=30)
            try:
                await session.get(f"{BASE}/")  # куки spid/spsc
            except Exception as e:
                raise StoreUnavailable(f"Купер: {e}") from e
            self._session = session
        return self._session

    async def _call(self, method: str, url: str, **kw: Any) -> Any:
        for attempt in (1, 2):
            session = await self._http(fresh=attempt == 2)
            try:
                resp = await session.request(method, url, **kw)
            except Exception as e:
                raise StoreUnavailable(f"Купер: {e}") from e
            if resp.status_code == 200 and "json" in (resp.headers.get("content-type") or ""):
                return resp.json()
            log.warning("Купер ответил %s (%s), попытка %s", resp.status_code,
                        resp.headers.get("content-type"), attempt)
        raise StoreUnavailable("Купер не пустил запрос (защита от ботов)")

    async def store_for(self, city: City) -> str | None:
        async with self._lock:
            if city.id not in self._store_for_city:
                payload = await self._call(
                    "GET", f"{BASE}/api/v3/mweb/shelves",
                    params={"lat": city.latitude, "lon": city.longitude, "shelves_codes_to_exclude": "alcohol"},
                    headers=HEADERS)
                self._store_for_city[city.id] = stores_from_shelves(payload).get(self.retailer.lower())
            return self._store_for_city[city.id]

    async def delivers_to(self, city: City) -> bool:
        return await self.store_for(city) is not None

    async def search(self, city: City, query: str) -> list[Offer]:
        store = await self.store_for(city)
        if store is None:
            return []
        payload = await self._call("POST", f"{BASE}/api/web/v1/products",
                                   data=json.dumps({"q": query[:200], "store_id": store}),
                                   headers={**HEADERS, "content-type": "application/json"})
        return parse_products(payload)

    async def close(self) -> None:
        if self._session is not None:
            await self._session.close()
            self._session = None
