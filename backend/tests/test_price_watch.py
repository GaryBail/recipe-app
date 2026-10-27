import asyncio
from datetime import datetime, timedelta, timezone
from decimal import Decimal

import pytest

from app.models import Offer, StoreInfo
from app.price_watch import MSK, PriceWatcher, hours_from_env, next_run
from tests.helpers import RecordingPush, make_client, register

DEVICE = "b" * 64


class PriceAdapter:
    def __init__(self, store_id, prices):
        self.info = StoreInfo(id=store_id, name=store_id)
        self.prices = prices
        self.calls = []

    async def delivers_to(self, city):
        return True

    async def search(self, city, query):
        self.calls.append(query)
        price = self.prices.get(query)
        if price is None:
            return []
        return [Offer(store_id=self.info.id, sku=query, title=f"{query} 200г", price=Decimal(price),
                      package_amount=200, unit="g")]

    async def close(self):
        pass


WATCH = {
    "name": "Моя карбонара",
    "recipe_title": "Паста карбонара",
    "city_id": "msk",
    "lines": [
        {"product_id": "parmesan", "query": "Сыр пармезан", "required_amount": 60, "unit": "g"},
        {"product_id": "pasta", "query": "Спагетти", "required_amount": 200, "unit": "g"},
    ],
}


@pytest.fixture
def setup(tmp_path):
    pyat = PriceAdapter("pyaterochka", {"Сыр пармезан": "300", "Спагетти": "100"})
    perek = PriceAdapter("perekrestok", {"Сыр пармезан": "350", "Спагетти": "90"})
    push = RecordingPush()
    with make_client(tmp_path, adapters=(pyat, perek), push=push) as client:
        moment = {"now": datetime(2026, 10, 20, 9, 0, tzinfo=timezone.utc)}  # 12:00 МСК
        s = client.app.state.stores
        watcher = PriceWatcher(s.watches, client.app.state.watcher.prices, s.notifications, s.auth, s.push,
                               delay=(0, 0), clock=lambda: moment["now"])
        yield client, watcher, moment, pyat, perek, push


def run(watcher):
    return asyncio.run(watcher.run_once())


def test_watch_crud_and_validation(setup):
    client, *_ = setup
    headers, _ = register(client)
    assert client.put("/watches/b1", json=WATCH).status_code == 401
    r = client.put("/watches/b1", json=WATCH, headers=headers)
    assert r.status_code == 200 and r.json()["name"] == "Моя карбонара"
    assert [w["client_id"] for w in client.get("/watches", headers=headers).json()] == ["b1"]

    spb = dict(WATCH, city_id="spb")
    assert client.put("/watches/b2", json=spb, headers=headers).status_code == 422

    assert client.delete("/watches/b1", headers=headers).status_code == 204
    assert client.get("/watches", headers=headers).json() == []


def test_watch_limit(setup):
    client, *_ = setup
    headers, _ = register(client)
    for i in range(20):
        assert client.put(f"/watches/w{i}", json=WATCH, headers=headers).status_code == 200
    assert client.put("/watches/w20", json=WATCH, headers=headers).status_code == 409


def test_refresh_dedupes_queries_and_computes_baskets(setup):
    client, watcher, moment, pyat, perek, _ = setup
    alice, _ = register(client)
    bob, _ = register(client)
    client.put("/watches/a", json=WATCH, headers=alice)
    client.put("/watches/b", json=WATCH, headers=bob)

    result = run(watcher)
    # два пользователя, одинаковые товары — по одному запросу на товар в каждом магазине
    assert sorted(pyat.calls) == ["Спагетти", "Сыр пармезан"]
    assert result["requests"] == {"pyaterochka": 2, "perekrestok": 2}

    watch = client.get("/watches/a", headers=alice).json()
    # 300 + 100 в Пятёрочке против 350 + 90 в Перекрёстке
    assert watch["best"] == {"store_id": "pyaterochka", "total": "400.00"}
    assert {s["store_id"]: s["total"] for s in watch["stores"]} == {"pyaterochka": "400.00",
                                                                    "perekrestok": "440.00"}


def test_daily_limit_reminder_and_price_drop(setup):
    client, watcher, moment, pyat, _, push = setup
    headers, _ = register(client)
    client.post("/devices", json={"token": DEVICE}, headers=headers)
    client.put("/watches/local-build-1", json=WATCH, headers=headers)

    # первый запуск — мягкое напоминание
    assert run(watcher)["notifications"] == 1
    items = client.get("/notifications", headers=headers).json()["items"]
    assert items[0]["kind"] == "reminder"
    assert items[0]["build_id"] == "local-build-1"
    assert "400 ₽" in items[0]["body"] and "Пятёрочке" in items[0]["body"]
    assert push.sent[-1]["data"] == {"kind": "reminder", "local_build_id": "local-build-1"}

    # в тот же день — ничего, даже если подешевело
    pyat.prices["Сыр пармезан"] = "100"
    moment["now"] += timedelta(hours=6)  # 18:00 МСК
    assert run(watcher)["notifications"] == 0

    # на следующий день — «подешевело»
    moment["now"] = datetime(2026, 10, 21, 9, 0, tzinfo=timezone.utc)
    assert run(watcher)["notifications"] == 1
    item = client.get("/notifications", headers=headers).json()["items"][0]
    assert item["kind"] == "price_drop"
    assert "дешевле обычного" in item["body"]

    # цена обычная и напоминали недавно — тишина
    moment["now"] = datetime(2026, 10, 22, 9, 0, tzinfo=timezone.utc)
    assert run(watcher)["notifications"] == 0


def test_no_notifications_at_night_or_when_disabled(setup):
    client, watcher, moment, *_ = setup
    headers, _ = register(client)
    client.put("/watches/x", json=WATCH, headers=headers)

    moment["now"] = datetime(2026, 10, 20, 4, 0, tzinfo=timezone.utc)  # 07:00 МСК
    assert run(watcher)["notifications"] == 0

    client.patch("/auth/me", json={"price_alerts": False}, headers=headers)
    moment["now"] = datetime(2026, 10, 20, 9, 0, tzinfo=timezone.utc)
    assert run(watcher)["notifications"] == 0


def test_store_errors_do_not_break_run(setup):
    client, watcher, moment, pyat, perek, _ = setup
    headers, _ = register(client)
    client.put("/watches/x", json=WATCH, headers=headers)

    async def broken(city, query):
        raise RuntimeError("капча")
    perek.search = broken
    result = run(watcher)
    assert result["requests"] == {"pyaterochka": 2, "perekrestok": 0}
    stores = client.get("/watches/x", headers=headers).json()["stores"]
    assert [s["store_id"] for s in stores] == ["pyaterochka"]


def test_changing_watch_resets_history(setup):
    client, watcher, *_ = setup
    headers, _ = register(client)
    client.put("/watches/x", json=WATCH, headers=headers)
    run(watcher)
    assert client.get("/watches/x", headers=headers).json()["best"] is not None
    changed = dict(WATCH, lines=WATCH["lines"][:1])
    assert client.put("/watches/x", json=changed, headers=headers).json()["best"] is None


def test_schedule():
    # 19:30 МСК → завтра 07:00
    assert next_run(datetime(2026, 10, 27, 16, 30, tzinfo=timezone.utc)) == datetime(2026, 10, 28, 7, tzinfo=MSK)
    # 11:00 МСК → 12:00
    assert next_run(datetime(2026, 10, 27, 8, 0, tzinfo=timezone.utc)) == datetime(2026, 10, 27, 12, tzinfo=MSK)
    assert hours_from_env("18, 9") == (9, 18)
    assert hours_from_env(None) == (7, 12, 18)
    with pytest.raises(ValueError):
        hours_from_env("25")


def test_account_deletion_removes_watches(setup):
    client, watcher, *_ = setup
    headers, _ = register(client)
    client.put("/watches/x", json=WATCH, headers=headers)
    client.delete("/auth/me", headers=headers)
    assert client.app.state.stores.watches.all() == []
