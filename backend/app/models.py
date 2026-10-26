"""Общие модели сервера. Без внешних зависимостей, чтобы легко тестировать."""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from decimal import Decimal
from typing import Any


@dataclass(frozen=True)
class City:
    id: str
    name: str
    latitude: float
    longitude: float


@dataclass(frozen=True)
class StoreInfo:
    id: str
    name: str
    app_scheme: str | None = None
    app_store_url: str | None = None
    web_url: str | None = None
    # Условия доставки пока не получаем автоматически — показываем пометку.
    delivery_fee: Decimal = Decimal(0)
    free_delivery_from: Decimal | None = None
    min_order: Decimal = Decimal(0)
    delivery_note: str | None = "Стоимость доставки уточняется в магазине"


@dataclass(frozen=True)
class Offer:
    """Товар в магазине с ценой и фасовкой."""

    store_id: str
    sku: str
    title: str
    price: Decimal  # рубли, текущая цена (с учётом скидки)
    package_amount: float  # сколько в упаковке; для весовых — 1000 г (цена за кг)
    unit: str  # "g" | "ml" | "pcs"
    in_stock: bool = True
    is_weighted: bool = False
    regular_price: Decimal | None = None  # цена без скидки, если есть
    image_url: str | None = None

    def to_json(self) -> dict[str, Any]:
        d = asdict(self)
        d["price"] = str(self.price)
        d["regular_price"] = str(self.regular_price) if self.regular_price is not None else None
        return d


@dataclass(frozen=True)
class CartLineRequest:
    product_id: str
    query: str
    required_amount: float
    unit: str


@dataclass
class Match:
    """Лучшее предложение под позицию корзины + альтернативы."""

    offer: Offer
    cost: Decimal
    relevance: float
    alternatives: list[Offer] = field(default_factory=list)

    def to_json(self) -> dict[str, Any]:
        return {
            "offer": self.offer.to_json(),
            "cost": str(self.cost),
            "relevance": round(self.relevance, 2),
            "alternatives": [a.to_json() for a in self.alternatives],
        }
