import json
from decimal import Decimal
from pathlib import Path

import pytest

from app.stores.perekrestok import parse_search
from app.stores.pyaterochka import parse_products
from app.units import parse_size

FIXTURES = Path(__file__).parent / "fixtures"


def load(name):
    return json.loads((FIXTURES / name).read_text(encoding="utf-8"))


@pytest.mark.parametrize("text, expected", [
    ("Молоко 3.2% Пр!ст, 970мл", (970, "ml")),
    ("Напиток газированный 1.5 л", (1500, "ml")),
    ("Сыр Пармезан 40%, 200г", (200, "g")),
    ("Мука пшеничная 2 кг", (2000, "g")),
    ("Яйца куриные С0 10шт", (10, "pcs")),
    ("Вода 6 х 0,5 л", (3000, "ml")),
    ("Цена за 1 кг", (1000, "g")),
    ("Перец чёрный молотый", None),
    ("Масло 72.5% Простоквашино", None),
])
def test_parse_size(text, expected):
    assert parse_size(text) == expected


def test_perekrestok_search_fixture():
    offers = parse_search(load("perekrestok_search.json"))
    assert len(offers) == 10
    milk = offers[0]
    assert milk.store_id == "perekrestok"
    assert milk.sku == "3431579"
    assert milk.price == Decimal("89.99")  # 8999 копеек
    assert (milk.package_amount, milk.unit) == (970, "ml")
    assert not milk.is_weighted
    assert all(o.price > 0 for o in offers)


def test_perekrestok_discount_keeps_regular_price():
    offers = parse_search(load("perekrestok_search.json"))
    discounted = [o for o in offers if o.regular_price is not None]
    assert discounted, "в фикстуре есть товары со скидкой"
    assert all(o.regular_price > o.price for o in discounted)


def test_pyaterochka_search_fixture():
    offers = parse_products(load("pyaterochka_search.json"))
    assert len(offers) > 3
    first = offers[0]
    assert first.store_id == "pyaterochka"
    assert first.sku == "4429993"
    assert first.price == Decimal("89.99")
    assert (first.package_amount, first.unit) == (1000, "ml")  # "1 л"


def test_pyaterochka_weighted_goods():
    offers = parse_products(load("pyaterochka_products_list.json"))
    weighted = [o for o in offers if o.is_weighted]
    assert weighted
    assert all(o.unit == "g" and o.package_amount == 1000 for o in weighted)


def test_perekrestok_handles_empty_payload():
    assert parse_search({}) == []
    assert parse_search({"content": {"products": None}}) == []
    assert parse_products({}) == []
