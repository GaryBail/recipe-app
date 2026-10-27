from __future__ import annotations

from typing import Protocol

from ..models import City, Offer, StoreInfo


class StoreUnavailable(Exception):
    """Сайт магазина недоступен: блокировка, капча, изменения на сайте или нет сети."""


class StoreAdapter(Protocol):
    """Адаптер одного магазина. Для каждого нового магазина пишется свой."""

    info: StoreInfo

    async def delivers_to(self, city: City) -> bool:
        """Есть ли доставка в город."""
        ...

    async def search(self, city: City, query: str) -> list[Offer]:
        """Поиск товаров по названию с ценами для города."""
        ...

    async def close(self) -> None: ...
