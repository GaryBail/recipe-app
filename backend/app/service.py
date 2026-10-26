"""Поиск цен по магазинам с кэшем."""

from __future__ import annotations

import asyncio
import logging
import time

from .matching import best_match
from .models import CartLineRequest, City, Match, Offer
from .stores.base import StoreAdapter

log = logging.getLogger(__name__)

CITIES: list[City] = [
    City("msk", "Москва", 55.7558, 37.6173),
    City("spb", "Санкт-Петербург", 59.9343, 30.3351),
    City("kzn", "Казань", 55.7963, 49.1088),
    City("ekb", "Екатеринбург", 56.8389, 60.6057),
    City("nsk", "Новосибирск", 55.0084, 82.9357),
    City("nnv", "Нижний Новгород", 56.3269, 44.0059),
]


class _TTLCache:
    def __init__(self, ttl_seconds: float):
        self.ttl = ttl_seconds
        self._data: dict[tuple, tuple[float, object]] = {}

    def get(self, key: tuple):
        item = self._data.get(key)
        if item and time.monotonic() - item[0] < self.ttl:
            return item[1]
        return None

    def put(self, key: tuple, value: object) -> None:
        self._data[key] = (time.monotonic(), value)


class PriceService:
    def __init__(self, adapters: list[StoreAdapter], cache_ttl: float = 3 * 3600):
        self.adapters = {a.info.id: a for a in adapters}
        self._search_cache = _TTLCache(cache_ttl)
        self._delivery_cache = _TTLCache(24 * 3600)

    def city(self, city_id: str) -> City | None:
        return next((c for c in CITIES if c.id == city_id), None)

    async def stores_for(self, city: City) -> list[StoreAdapter]:
        async def check(adapter: StoreAdapter) -> StoreAdapter | None:
            key = (adapter.info.id, city.id)
            cached = self._delivery_cache.get(key)
            if cached is None:
                try:
                    cached = await adapter.delivers_to(city)
                except Exception:
                    log.exception("delivers_to failed: %s %s", adapter.info.id, city.id)
                    return None
                self._delivery_cache.put(key, cached)
            return adapter if cached else None

        result = await asyncio.gather(*(check(a) for a in self.adapters.values()))
        return [a for a in result if a is not None]

    async def search(self, store_id: str, city: City, query: str) -> list[Offer]:
        key = (store_id, city.id, query.strip().lower())
        cached = self._search_cache.get(key)
        if cached is not None:
            return cached  # type: ignore[return-value]
        offers = await self.adapters[store_id].search(city, query)
        self._search_cache.put(key, offers)
        return offers

    async def match_lines(self, store_id: str, city: City, lines: list[CartLineRequest]) -> dict[str, Match]:
        result: dict[str, Match] = {}
        for line in lines:  # адаптер всё равно обрабатывает запросы по очереди
            try:
                offers = await self.search(store_id, city, line.query)
            except Exception:
                log.exception("search failed: %s %s %r", store_id, city.id, line.query)
                continue
            match = best_match(line.query, offers, line.required_amount, line.unit)
            if match:
                result[line.product_id] = match
        return result

    async def close(self) -> None:
        for a in self.adapters.values():
            try:
                await a.close()
            except Exception:
                log.exception("close failed: %s", a.info.id)
