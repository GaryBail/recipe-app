"""Адаптеры Ленты, Магнита, Ашана и Купера на сохранённых ответах их API (Санкт-Петербург, октябрь 2026)."""

import asyncio
import json
from decimal import Decimal
from pathlib import Path

import pytest

from app.matching import best_match
from app.models import City
from app.stores import auchan, kuper, lenta, magnit
from app.stores.base import StoreUnavailable

FIXTURES = Path(__file__).parent / "fixtures"
SPB = City("spb", "Санкт-Петербург", 59.9343, 30.3351)
KZN = City("kzn", "Казань", 55.7963, 49.1088)


def load(name):
    return json.loads((FIXTURES / name).read_text(encoding="utf-8"))


def run(coro):
    return asyncio.run(coro)


class FakeResponse:
    def __init__(self, payload, status=200, ctype="application/json"):
        self.status_code = status
        self.headers = {"content-type": ctype}
        self._payload = payload

    def json(self):
        return self._payload


class FakeClient:
    """Отвечает по пути запроса; записывает запросы."""

    def __init__(self, routes):
        self.routes = routes
        self.calls = []

    def _answer(self, method, path, kw):
        self.calls.append((method, path, kw))
        for key, value in self.routes.items():
            if key in path:
                return value if isinstance(value, FakeResponse) else FakeResponse(value)
        return FakeResponse({}, status=404)

    async def get(self, path, **kw):
        return self._answer("GET", path, kw)

    async def post(self, path, **kw):
        return self._answer("POST", path, kw)

    async def request(self, method, path, **kw):
        return self._answer(method, path, kw)

    async def aclose(self):
        pass


# ---------- Лента ----------

def test_lenta_packaged_goods_in_rubles():
    offers = lenta.parse_items(load("lenta_search_milk.json"))
    milk = offers[0]
    assert milk.store_id == "lenta" and milk.sku == "1333"
    assert milk.price == Decimal("99.99") and milk.regular_price == Decimal("119.99")
    assert (milk.package_amount, milk.unit, milk.is_weighted) == (930, "ml", False)
    assert milk.image_url.startswith("https://cdn.api.lenta.com/")


def test_lenta_weighted_goods_priced_per_kg():
    potatoes = {o.title: o for o in lenta.parse_items(load("lenta_search_potato.json"))}
    washed = potatoes["Картофель белый мытый, весовой"]
    # кусок ~500 г за 35 ₽, а за килограмм — 69,99 ₽
    assert washed.is_weighted and (washed.package_amount, washed.unit) == (1000, "g")
    assert washed.price == Decimal("69.99")
    fries = potatoes["Картофель фри BONVIDA, 1,5кг"]
    assert (fries.package_amount, fries.unit, fries.is_weighted) == (1500, "g", False)


def test_lenta_picks_hypermarket_near_city_center():
    store = lenta.pick_store(load("lenta_stores.json")["stores"], SPB)
    assert store["type"] == "hypermarket"
    assert lenta.pick_store(load("lenta_stores.json")["stores"], KZN) is None


def test_lenta_adapter_search():
    client = FakeClient({"/v1/stores": load("lenta_stores.json"),
                         "/catalog/v1/items": load("lenta_search_parmesan.json")})
    adapter = lenta.LentaAdapter(client=client)
    assert run(adapter.delivers_to(SPB))
    offers = run(adapter.search(SPB, "пармезан"))
    assert offers and all(o.store_id == "lenta" for o in offers)
    method, path, kw = client.calls[-1]
    assert kw["params"]["channel"] == "lo" and kw["params"]["retailBrand"] == "lo"
    assert kw["params"]["query"] == "пармезан"
    # 200 г пармезана: весовой по цене за кг против упаковки 180 г
    match = best_match("пармезан", offers, 200, "g")
    assert match is not None and match.cost > 0


def test_lenta_errors_are_store_unavailable():
    adapter = lenta.LentaAdapter(client=FakeClient({"/v1/stores": FakeResponse({}, status=403)}))
    with pytest.raises(StoreUnavailable):
        run(adapter.search(SPB, "молоко"))


# ---------- Магнит ----------

def test_magnit_parse_goods():
    offers = magnit.parse_goods(load("magnit_search_milk.json"))
    first = offers[0]
    assert first.store_id == "magnit" and first.price == Decimal("109.99")
    assert (first.package_amount, first.unit) == (1000, "ml")


def test_magnit_weighted_portion_is_a_package():
    offers = {o.title: o for o in magnit.parse_goods(load("magnit_search_potato.json"))}
    potato = offers["Картофель"]  # пакет 2 кг за 124 ₽
    assert (potato.package_amount, potato.unit, potato.is_weighted) == (2000, "g", False)
    assert potato.price == Decimal("124.00")
    promo = offers["Овощи по-деревенски Agama с картофелем быстрозамороженные 400г"]
    assert promo.regular_price == Decimal("199.00") and promo.price == Decimal("124.00")


def test_magnit_nearest_store_and_search():
    assert magnit.nearest_store(load("magnit_stores.json"), SPB) == "699422"
    client = FakeClient({"stores-facade/search": load("magnit_stores.json"),
                         "goods/search": load("magnit_search_parmesan.json")})
    adapter = magnit.MagnitAdapter(client=client)
    offers = run(adapter.search(SPB, "пармезан"))
    assert offers
    _, _, kw = client.calls[-1]
    assert kw["json"]["storeCode"] == "699422" and kw["json"]["storeType"] == "express"


def test_magnit_no_store_nearby():
    adapter = magnit.MagnitAdapter(client=FakeClient({"stores-facade/search": {"items": {"items": []}}}))
    assert not run(adapter.delivers_to(KZN))
    assert run(adapter.search(KZN, "молоко")) == []


# ---------- Ашан ----------

def test_auchan_units():
    offers = {o.title: o for o in auchan.parse_search(load("auchan_search_parmesan.json"))}
    per_100g = next(o for t, o in offers.items() if t.startswith("Сыр полутвердый Пармезан Янг"))
    assert per_100g.is_weighted and per_100g.price == Decimal("1200.00")  # 120 ₽ за 100 г
    natura = next(o for t, o in offers.items() if "Natura" in t)
    assert (natura.package_amount, natura.unit) == (180, "g") and natura.price == Decimal("229.99")
    sweet = next(o for o in auchan.parse_search(load("auchan_search_potato.json")) if "батат" in o.title)
    assert sweet.is_weighted and sweet.regular_price == Decimal("279.99")


def test_auchan_eggs_count_from_title_not_package():
    eggs = auchan.parse_search(load("auchan_search_eggs.json"))
    assert (eggs[0].package_amount, eggs[0].unit) == (10, "pcs")  # в package_display ошибочно «10 кг»
    assert (eggs[1].package_amount, eggs[1].unit) == (30, "pcs")


def test_auchan_shop_and_search():
    shops = load("auchan_shops.json")["shops"]
    shop = auchan.pick_shop(shops, SPB)
    assert shop is not None and shop["region_id"] == 2
    client = FakeClient({"/v1/shops": load("auchan_shops.json"), "/v1/search": load("auchan_search_potato.json")})
    adapter = auchan.AuchanAdapter(client=client)
    offers = run(adapter.search(SPB, "картофель"))
    assert offers and len(offers) <= auchan.MAX_RESULTS
    method, path, kw = client.calls[-1]
    assert method == "POST" and kw["params"]["merchantId"] == shop["merchant_id"]


def test_auchan_html_challenge_is_unavailable():
    client = FakeClient({"/v1/shops": FakeResponse("<html>", ctype="text/html")})
    with pytest.raises(StoreUnavailable):
        run(auchan.AuchanAdapter(client=client).search(SPB, "молоко"))


# ---------- Купер ----------

def test_kuper_stores_from_shelves():
    stores = kuper.stores_from_shelves(load("kuper_shelves.json"))
    assert stores["лента"] == "135212" and stores["ашан"] == "276" and stores["магнит"] == "3879"


def test_kuper_parse_products():
    potatoes = kuper.parse_products(load("kuper_lenta_potato.json"))
    assert potatoes[0].is_weighted and potatoes[0].price == Decimal("101.99")
    baby = next(o for o in potatoes if "Беби" in o.title)  # per_package, 2 кг
    assert (baby.package_amount, baby.unit, baby.is_weighted) == (2000, "g", False)
    eggs = kuper.parse_products(load("kuper_magnit_eggs.json"))
    assert (eggs[0].package_amount, eggs[0].unit) == (10, "pcs")  # «10 шт» в названии, а не 600 г
    cheese = kuper.parse_products(load("kuper_auchan_parmesan.json"))
    discounted = next(o for o in cheese if o.regular_price)
    assert discounted.regular_price > discounted.price


class FakeKuperSession:
    def __init__(self, answers):
        self.answers = list(answers)
        self.calls = []

    async def request(self, method, url, **kw):
        self.calls.append((method, url, kw))
        return self.answers.pop(0)

    async def get(self, url, **kw):
        return FakeResponse({})

    async def close(self):
        pass


def test_kuper_adapter_uses_retailer_store():
    session = FakeKuperSession([FakeResponse(load("kuper_shelves.json")),
                                FakeResponse(load("kuper_lenta_potato.json"))])
    adapter = kuper.KuperAdapter("Лента", session=session)
    assert adapter.info.name == "Купер · Лента"
    offers = run(adapter.search(SPB, "картофель"))
    assert offers
    _, url, kw = session.calls[-1]
    assert url.endswith("/api/web/v1/products") and json.loads(kw["data"])["store_id"] == "135212"


def test_kuper_bot_check_is_unavailable(monkeypatch):
    challenge = FakeResponse("<html>", ctype="text/html")
    session = FakeKuperSession([challenge, challenge])
    adapter = kuper.KuperAdapter("Лента", session=session)

    async def same_session(fresh=False):
        return session
    monkeypatch.setattr(adapter, "_http", same_session)
    with pytest.raises(StoreUnavailable):
        run(adapter.search(SPB, "молоко"))
