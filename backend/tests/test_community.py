import uuid

import pytest
from fastapi.testclient import TestClient

from app.community import CommunityStore, bayesian_score
from app.main import create_app
from app.service import PriceService

ALICE = str(uuid.uuid4())
BOB = str(uuid.uuid4())
CAROL = str(uuid.uuid4())


def h(user):
    return {"X-User-Id": user}


def build_payload(name="Моя карбонара", recipe_id="carbonara", product="Пармезан"):
    return {
        "author_name": "Алиса",
        "name": name,
        "recipe": {
            "id": recipe_id, "title": "Паста карбонара", "summary": "", "servings": 2,
            "steps": ["Сварить пасту"],
            "ingredients": [
                {"id": "c-cheese", "title": "Твёрдый сыр", "category_id": "hard-cheese", "amount": 60, "unit": "g"},
            ],
        },
        "items": [
            {"ingredient_id": "c-cheese",
             "product": {"id": "parmesan", "name": product, "brand": None, "category_id": "hard-cheese"}},
        ],
    }


@pytest.fixture
def client(tmp_path):
    store = CommunityStore(str(tmp_path / "test.db"))
    with TestClient(create_app(PriceService([]), store)) as c:
        yield c
    store.close()


def test_requires_user_id(client):
    assert client.get("/community/builds").status_code == 401
    assert client.get("/community/builds", headers=h("not-a-uuid")).status_code == 401


def test_publish_and_list(client):
    r = client.post("/community/builds", json=build_payload(), headers=h(ALICE))
    assert r.status_code == 201
    build = r.json()
    assert build["author_name"] == "Алиса"
    assert build["items"][0]["product"]["name"] == "Пармезан"
    assert build["rating_count"] == 0

    listed = client.get("/community/builds", params={"recipe_id": "carbonara"}, headers=h(BOB)).json()
    assert [b["id"] for b in listed] == [build["id"]]
    assert client.get("/community/builds", params={"recipe_id": "other"}, headers=h(BOB)).json() == []


def test_publish_validation(client):
    bad = build_payload()
    bad["items"][0]["ingredient_id"] = "missing"
    assert client.post("/community/builds", json=bad, headers=h(ALICE)).status_code == 422


def test_rating_and_ranking(client):
    a = client.post("/community/builds", json=build_payload("A"), headers=h(ALICE)).json()
    b = client.post("/community/builds", json=build_payload("B"), headers=h(ALICE)).json()

    # нельзя оценить свою
    assert client.put(f"/community/builds/{a['id']}/rating", json={"stars": 5}, headers=h(ALICE)).status_code == 403

    client.put(f"/community/builds/{a['id']}/rating", json={"stars": 3}, headers=h(BOB))
    client.put(f"/community/builds/{b['id']}/rating", json={"stars": 5, "comment": "Отлично"}, headers=h(BOB))
    r = client.put(f"/community/builds/{b['id']}/rating", json={"stars": 4}, headers=h(CAROL))
    assert r.json()["rating_count"] == 2
    assert r.json()["rating_avg"] == 4.5

    # повторная оценка заменяет предыдущую
    r = client.put(f"/community/builds/{a['id']}/rating", json={"stars": 2}, headers=h(BOB))
    assert r.json()["rating_count"] == 1 and r.json()["my_rating"] == 2

    top = client.get("/community/builds", params={"sort": "top"}, headers=h(BOB)).json()
    assert [x["name"] for x in top] == ["B", "A"]

    ratings = client.get(f"/community/builds/{b['id']}/ratings", headers=h(ALICE)).json()
    assert {x["stars"] for x in ratings} == {4, 5}


def test_bayesian_score_prefers_many_good_ratings():
    assert bayesian_score(5.0, 1) < bayesian_score(4.8, 100)
    assert bayesian_score(None, 0) == 3.5


def test_reports_hide_build(client):
    b = client.post("/community/builds", json=build_payload(), headers=h(ALICE)).json()
    for _ in range(3):
        reporter = str(uuid.uuid4())
        assert client.post(f"/community/builds/{b['id']}/report", json={"reason": "спам"},
                           headers=h(reporter)).status_code == 204
    assert client.get(f"/community/builds/{b['id']}", headers=h(BOB)).status_code == 404


def test_same_user_reports_count_once(client):
    b = client.post("/community/builds", json=build_payload(), headers=h(ALICE)).json()
    for _ in range(3):
        client.post(f"/community/builds/{b['id']}/report", json={"reason": "спам"}, headers=h(BOB))
    assert client.get(f"/community/builds/{b['id']}", headers=h(CAROL)).status_code == 200


def test_block_hides_author(client):
    client.post("/community/builds", json=build_payload(), headers=h(ALICE))
    assert client.post("/community/blocks", json={"user_id": ALICE}, headers=h(BOB)).status_code == 204
    assert client.get("/community/builds", headers=h(BOB)).json() == []
    assert len(client.get("/community/builds", headers=h(CAROL)).json()) == 1


def test_delete_only_own(client):
    b = client.post("/community/builds", json=build_payload(), headers=h(ALICE)).json()
    assert client.delete(f"/community/builds/{b['id']}", headers=h(BOB)).status_code == 404
    assert client.delete(f"/community/builds/{b['id']}", headers=h(ALICE)).status_code == 204
    assert client.get("/community/builds", headers=h(ALICE)).json() == []


def test_mine_filter(client):
    client.post("/community/builds", json=build_payload(), headers=h(ALICE))
    assert len(client.get("/community/builds", params={"mine": True}, headers=h(ALICE)).json()) == 1
    assert client.get("/community/builds", params={"mine": True}, headers=h(BOB)).json() == []
