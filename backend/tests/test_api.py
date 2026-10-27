from decimal import Decimal

from fastapi.testclient import TestClient

from app.main import create_app
from app.models import City, Offer, StoreInfo
from app.service import PriceService


class FakeAdapter:
    def __init__(self, store_id, offers, delivers=True):
        self.info = StoreInfo(id=store_id, name=store_id.title())
        self._offers = offers
        self._delivers = delivers
        self.search_calls = 0

    async def delivers_to(self, city: City) -> bool:
        return self._delivers

    async def search(self, city: City, query: str):
        self.search_calls += 1
        return self._offers

    async def close(self):
        pass


import pytest


@pytest.fixture
def make_client(tmp_path):
    def factory(*adapters):
        return TestClient(create_app(PriceService(list(adapters)), db_path=str(tmp_path / "t.db")))
    return factory


CHEESE = Offer(store_id="a", sku="1", title="Сыр Пармезан 200г", price=Decimal("399.90"),
               package_amount=200, unit="g")


def test_cities_and_stores(make_client):
    with make_client(FakeAdapter("a", [CHEESE]), FakeAdapter("b", [], delivers=False)) as client:
        assert any(c["id"] == "msk" for c in client.get("/cities").json())
        stores = client.get("/stores", params={"city": "msk"}).json()
        assert [s["id"] for s in stores] == ["a"]
        assert client.get("/stores", params={"city": "nowhere"}).status_code == 404


def test_offers_matches_and_caches(make_client):
    adapter = FakeAdapter("a", [CHEESE])
    with make_client(adapter) as client:
        body = {"store": "a", "city": "msk", "lines": [
            {"product_id": "parmesan", "query": "Пармезан", "required_amount": 60, "unit": "g"},
            {"product_id": "eggs", "query": "Яйца С0", "required_amount": 3, "unit": "pcs"},
        ]}
        data = client.post("/offers", json=body).json()["offers"]
        assert set(data) == {"parmesan"}
        assert data["parmesan"]["offer"]["price"] == "399.90"
        assert data["parmesan"]["cost"] == "399.90"

        client.post("/offers", json=body)
        assert adapter.search_calls == 2  # второй запрос пришёл из кэша


def test_offers_validation(make_client):
    with make_client(FakeAdapter("a", [])) as client:
        bad = {"store": "a", "city": "msk", "lines": [
            {"product_id": "x", "query": "Сыр", "required_amount": 0, "unit": "kg"}]}
        assert client.post("/offers", json=bad).status_code == 422
        assert client.post("/offers", json={"store": "zzz", "city": "msk", "lines": []}).status_code == 404
