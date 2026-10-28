"""Лента через открытый Integration API (https://integration.api.lenta.com, описание — lenta.com/llms.txt).

Официальный API только для чтения: магазины, категории, поиск и карточки товаров. Ключ не нужен.
Цены зависят от магазина и канала продаж; берём гипермаркет, ближайший к центру города
(в нём самый широкий ассортимент), и канал «lo» — доставка Ленты Онлайн.
Корзину через API передать нельзя.
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

STORE_ID = "lenta"
API_URL = "https://integration.api.lenta.com"
RETAIL_BRAND = "lo"
CHANNEL = "lo"
MAX_DISTANCE_M = 40_000          # магазин дальше 40 км от центра — считаем, что в городе Ленты нет
STORE_TYPES = ("hypermarket", "supermarket", "AL", "EC")  # по убыванию ассортимента; zoo — зоомагазины

INFO = StoreInfo(id=STORE_ID, name="Лента", web_url="https://lenta.com")


def _rub(kopecks: Any) -> Decimal | None:
    if kopecks is None:
        return None
    return (Decimal(int(kopecks)) / 100).quantize(Decimal("0.01"))


def pick_store(stores: list[dict[str, Any]], city: City) -> dict[str, Any] | None:
    """Самый крупный формат среди магазинов в радиусе города, из них — ближайший к центру."""
    near = []
    for s in stores:
        if s.get("type") not in STORE_TYPES or s.get("lat") is None or s.get("long") is None:
            continue
        d = distance_m(city.latitude, city.longitude, float(s["lat"]), float(s["long"]))
        if d <= MAX_DISTANCE_M:
            near.append((STORE_TYPES.index(s["type"]), d, s))
    if not near:
        return None
    return min(near, key=lambda x: (x[0], x[1]))[2]


def parse_items(payload: dict[str, Any]) -> list[Offer]:
    """Ответ /catalog/v1/items → предложения. Цены в копейках.

    Весовой товар (isWeight) продаётся кусками примерно известного веса, а оплачивается по факту:
    `cost` — цена за килограмм, `price` — за кусок весом `weight.net`. Считаем такие товары по весу.
    """
    offers: list[Offer] = []
    for item in payload.get("items") or []:
        prices = item.get("prices") or {}
        if item.get("id") is None or prices.get("price") is None:
            continue
        title = " ".join(str(item.get("name") or "").split())
        weight = item.get("weight") or {}
        weighted = bool(item.get("isWeight") or (item.get("features") or {}).get("isWeight"))
        if weighted:
            price = _rub(prices.get("cost") or prices["price"])
            regular = _rub(prices.get("costRegular"))
            amount, unit = 1000.0, "g"
        else:
            price = _rub(prices["price"])
            regular = _rub(prices.get("priceRegular"))
            size = parse_size(weight.get("package")) or parse_size(title)
            amount, unit = size if size else (1.0, "pcs")
        assert price is not None
        offers.append(Offer(
            store_id=STORE_ID,
            sku=str(item["id"]),
            title=title,
            price=price,
            package_amount=amount,
            unit=unit,
            in_stock=(item.get("count") or 0) > 0,
            is_weighted=weighted,
            regular_price=regular if regular is not None and regular > price else None,
            image_url=next((i.get("pathMedium") for i in item.get("images") or [] if i.get("pathMedium")), None),
        ))
    return offers


class LentaAdapter:
    info = INFO

    def __init__(self, client: Any = None, base_url: str = API_URL):
        self._client = client
        self._base_url = base_url
        self._stores: list[dict[str, Any]] | None = None
        self._store_for_city: dict[str, str | None] = {}
        self._lock = asyncio.Lock()

    async def _http(self) -> Any:
        if self._client is None:
            import httpx
            self._client = httpx.AsyncClient(base_url=self._base_url, timeout=25,
                                             headers={"Accept": "application/json", "User-Agent": "VyborVkusa/1.0"})
        return self._client

    async def _get(self, path: str, params: dict[str, Any]) -> Any:
        client = await self._http()
        try:
            resp = await client.get(path, params={"retailBrand": RETAIL_BRAND, **params})
        except Exception as e:  # сеть, таймаут
            raise StoreUnavailable(f"Лента: {e}") from e
        if resp.status_code >= 400:
            raise StoreUnavailable(f"Лента: HTTP {resp.status_code}")
        return resp.json()

    async def store_for(self, city: City) -> str | None:
        async with self._lock:
            if city.id not in self._store_for_city:
                if self._stores is None:
                    self._stores = (await self._get("/v1/stores", {})).get("stores") or []
                store = pick_store(self._stores, city)
                self._store_for_city[city.id] = str(store["id"]) if store else None
                if store:
                    log.info("Лента %s: магазин %s (%s, %s)", city.id, store["id"], store.get("type"),
                             store.get("address"))
            return self._store_for_city[city.id]

    async def delivers_to(self, city: City) -> bool:
        return await self.store_for(city) is not None

    async def search(self, city: City, query: str) -> list[Offer]:
        store = await self.store_for(city)
        if store is None:
            return []
        payload = await self._get("/catalog/v1/items", {"stores": store, "channel": CHANNEL,
                                                         "query": query[:200], "limit": 20})
        return parse_items(payload)

    async def close(self) -> None:
        if self._client is not None:
            await self._client.aclose()
            self._client = None
