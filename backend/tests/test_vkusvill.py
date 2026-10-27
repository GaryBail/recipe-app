import asyncio
import json
from decimal import Decimal

import pytest

from app.models import City
from app.stores.base import StoreUnavailable
from app.stores.vkusvill import VkusVillAdapter, cart_quantity, parse_search

# Ответ поиска в том виде, как его вернул сервер ВкусВилл (сокращён до трёх товаров).
SEARCH = {
    "ok": True,
    "data": {
        "meta": {"q": "пармезан", "limit": 3, "total": 62},
        "items": [
            {"id": 115018, "name": "Сыр \"Пармезан\" 45% (6 мес.) тёртый, 90&nbsp;г",
             "price": {"current": 236, "currency": "RUB", "old": None},
             "unit": "шт", "weight": {"value": 0.09, "unit": "кг"}},
            {"id": 113215, "name": "Сыр Schonfeld Пармезан 40% твердый тертый",
             "price": {"current": 175, "currency": "RUB", "old": 199},
             "unit": "шт", "weight": {"value": 0.08, "unit": "кг"}},
            {"id": 15807, "name": "Сыр \"Пармезан молодой\"",
             "price": {"current": 1485, "currency": "RUB", "old": None}, "unit": "кг"},
        ],
    },
}

MSK = City("msk", "Москва", 0, 0)


def test_parse_search():
    offers = parse_search(SEARCH)
    assert [o.sku for o in offers] == ["115018", "113215", "15807"]
    grated = offers[0]
    assert grated.title == "Сыр \"Пармезан\" 45% (6 мес.) тёртый, 90 г"
    assert grated.price == Decimal("236.00")
    assert (grated.package_amount, grated.unit, grated.is_weighted) == (90, "g", False)
    # фасовки нет в названии — берём вес из карточки
    assert (offers[1].package_amount, offers[1].unit) == (80, "g")
    assert offers[1].regular_price == Decimal("199.00")
    # весовой товар: цена за килограмм
    assert (offers[2].package_amount, offers[2].unit, offers[2].is_weighted) == (1000, "g", True)


def test_cart_quantity_limits():
    assert cart_quantity(0.001) == 0.01
    assert cart_quantity(2) == 2
    assert cart_quantity(100) == 40


class FakeResponse:
    def __init__(self, payload, sse=False, session=None, status=200):
        self.status_code = status
        self.headers = {"content-type": "text/event-stream" if sse else "application/json"}
        if session:
            self.headers["mcp-session-id"] = session
        body = json.dumps(payload, ensure_ascii=False) if payload is not None else ""
        self.text = f"event: message\ndata: {body}\n\n" if sse else body


class FakeMCP:
    """Изображает сервер ВкусВилл: initialize → session id, затем tools/call."""

    def __init__(self):
        self.calls = []

    async def post(self, url, content, headers):
        body = json.loads(content)
        self.calls.append((body.get("method"), headers.get("Mcp-Session-Id")))
        method = body.get("method")
        if method == "initialize":
            return FakeResponse({"jsonrpc": "2.0", "id": body["id"], "result": {}}, session="s1")
        if method == "notifications/initialized":
            return FakeResponse(None, status=202)
        name = body["params"]["name"]
        if name == "vkusvill_products_search":
            result = SEARCH
        else:
            ids = [p["id"] for p in body["params"]["arguments"]["products"]]
            result = {"ok": True, "data": {"link": f"https://vkusvill.ru/mobile?basket&share={sum(ids)}"}}
        return FakeResponse({"jsonrpc": "2.0", "id": body["id"],
                             "result": {"content": [{"type": "text", "text": json.dumps(result)}],
                                        "isError": False}}, sse=True)

    async def aclose(self):
        pass


def test_adapter_search_and_cart_link():
    fake = FakeMCP()
    adapter = VkusVillAdapter(client=fake)

    async def run():
        offers = await adapter.search(MSK, "пармезан")
        link = await adapter.cart_link([("115018", 2), ("15807", 0.06), ("not-a-number", 1)])
        return offers, link

    offers, link = asyncio.run(run())
    assert len(offers) == 3
    assert link == "https://vkusvill.ru/mobile?basket&share=130825"
    # сессия открывается один раз и передаётся в следующих запросах
    assert [m for m, _ in fake.calls].count("initialize") == 1
    assert fake.calls[-1] == ("tools/call", "s1")


def test_adapter_reports_unavailable():
    class Broken(FakeMCP):
        async def post(self, url, content, headers):
            raise OSError("network down")

    adapter = VkusVillAdapter(client=Broken())
    with pytest.raises(StoreUnavailable):
        asyncio.run(adapter.search(MSK, "молоко"))


def test_delivers_only_to_known_cities():
    adapter = VkusVillAdapter(client=FakeMCP())
    assert asyncio.run(adapter.delivers_to(MSK))
    assert not asyncio.run(adapter.delivers_to(City("nsk", "Новосибирск", 0, 0)))
