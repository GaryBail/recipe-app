import pytest

from app.community import bayesian_score
from tests.helpers import build_payload, make_client, register


@pytest.fixture
def client(tmp_path):
    with make_client(tmp_path) as c:
        yield c


@pytest.fixture
def users(client):
    alice, alice_user = register(client, name="Алиса")
    bob, bob_user = register(client, name="Боб")
    carol, _ = register(client, name="Карина")
    return {"alice": alice, "bob": bob, "carol": carol, "alice_id": alice_user["id"]}


def payload(name="Моя карбонара", recipe_id="carbonara"):
    p = build_payload()
    p["name"] = name
    p["recipe"]["id"] = recipe_id
    return p


def test_writes_require_login(client):
    assert client.post("/community/builds", json=payload()).status_code == 401
    assert client.get("/community/builds", params={"mine": True}).status_code == 401
    # читать можно без входа
    assert client.get("/community/builds").status_code == 200


def test_publish_uses_account_name(client, users):
    r = client.post("/community/builds", json=payload(), headers=users["alice"])
    assert r.status_code == 201
    build = r.json()
    assert build["author_name"] == "Алиса"
    assert build["author_id"] == users["alice_id"]

    listed = client.get("/community/builds", params={"recipe_id": "carbonara"}).json()
    assert [b["id"] for b in listed] == [build["id"]]
    assert client.get("/community/builds", params={"recipe_id": "other"}).json() == []


def test_publish_validation(client, users):
    bad = payload()
    bad["items"][0]["ingredient_id"] = "missing"
    assert client.post("/community/builds", json=bad, headers=users["alice"]).status_code == 422


def test_rating_and_ranking(client, users):
    a = client.post("/community/builds", json=payload("A"), headers=users["alice"]).json()
    b = client.post("/community/builds", json=payload("B"), headers=users["alice"]).json()

    assert client.put(f"/community/builds/{a['id']}/rating", json={"stars": 5},
                      headers=users["alice"]).status_code == 403

    client.put(f"/community/builds/{a['id']}/rating", json={"stars": 3}, headers=users["bob"])
    client.put(f"/community/builds/{b['id']}/rating", json={"stars": 5, "comment": "Отлично"}, headers=users["bob"])
    r = client.put(f"/community/builds/{b['id']}/rating", json={"stars": 4}, headers=users["carol"])
    assert r.json()["rating_count"] == 2
    assert r.json()["rating_avg"] == 4.5

    r = client.put(f"/community/builds/{a['id']}/rating", json={"stars": 2}, headers=users["bob"])
    assert r.json()["rating_count"] == 1 and r.json()["my_rating"] == 2

    top = client.get("/community/builds", params={"sort": "top"}).json()
    assert [x["name"] for x in top] == ["B", "A"]

    ratings = client.get(f"/community/builds/{b['id']}/ratings").json()
    assert {(x["author_name"], x["stars"]) for x in ratings} == {("Боб", 5), ("Карина", 4)}


def test_bayesian_score_prefers_many_good_ratings():
    assert bayesian_score(5.0, 1) < bayesian_score(4.8, 100)
    assert bayesian_score(None, 0) == 3.5


def test_reports_hide_build(client, users):
    b = client.post("/community/builds", json=payload(), headers=users["alice"]).json()
    for _ in range(3):
        reporter, _ = register(client)
        assert client.post(f"/community/builds/{b['id']}/report", json={"reason": "спам"},
                           headers=reporter).status_code == 204
    assert client.get(f"/community/builds/{b['id']}").status_code == 404


def test_same_user_reports_count_once(client, users):
    b = client.post("/community/builds", json=payload(), headers=users["alice"]).json()
    for _ in range(3):
        client.post(f"/community/builds/{b['id']}/report", json={"reason": "спам"}, headers=users["bob"])
    assert client.get(f"/community/builds/{b['id']}").status_code == 200


def test_block_hides_author(client, users):
    client.post("/community/builds", json=payload(), headers=users["alice"])
    assert client.post("/community/blocks", json={"user_id": users["alice_id"]},
                       headers=users["bob"]).status_code == 204
    assert client.get("/community/builds", headers=users["bob"]).json() == []
    assert len(client.get("/community/builds", headers=users["carol"]).json()) == 1


def test_delete_only_own(client, users):
    b = client.post("/community/builds", json=payload(), headers=users["alice"]).json()
    assert client.delete(f"/community/builds/{b['id']}", headers=users["bob"]).status_code == 404
    assert client.delete(f"/community/builds/{b['id']}", headers=users["alice"]).status_code == 204
    assert client.get("/community/builds").json() == []


def test_mine_filter(client, users):
    client.post("/community/builds", json=payload(), headers=users["alice"])
    assert len(client.get("/community/builds", params={"mine": True}, headers=users["alice"]).json()) == 1
    assert client.get("/community/builds", params={"mine": True}, headers=users["bob"]).json() == []


def user_recipe_payload(name, recipe_id="user-abc", product="parmesan", product_name="Пармезан"):
    p = payload(name, recipe_id)
    p["recipe"]["title"] = "Паста бабушки"
    p["recipe"]["rubric"] = "main"
    p["recipe"]["cook_minutes"] = 30
    p["items"][0]["product"] = {"id": product, "name": product_name, "category_id": "hc"}
    return p


def test_user_recipes_feed(client, users):
    # каталожные рецепты в ленту рецептов не попадают
    client.post("/community/builds", json=payload(), headers=users["alice"])
    first = client.post("/community/builds", json=user_recipe_payload("Оригинал"), headers=users["alice"]).json()
    client.post("/community/builds", json=user_recipe_payload("Вариант Боба", product="grana", product_name="Грана"),
                headers=users["bob"])
    client.put(f"/community/builds/{first['id']}/rating", json={"stars": 5}, headers=users["bob"])

    recipes = client.get("/community/recipes").json()
    assert len(recipes) == 1
    r = recipes[0]
    assert r["recipe"]["id"] == "user-abc"
    assert r["recipe"]["rubric"] == "main" and r["recipe"]["cook_minutes"] == 30
    assert r["author_name"] == "Алиса"
    assert r["builds_count"] == 2
    assert r["rating_count"] == 1 and r["rating_avg"] == 5
    assert r["best_build_id"] == first["id"]
    assert client.get("/community/recipes", params={"sort": "bad"}).status_code == 422


def test_popular_choices(client, users):
    for who, product, name in [("alice", "parmesan", "Пармезан"), ("bob", "parmesan", "Пармезан"),
                               ("carol", "grana", "Грана")]:
        client.post("/community/builds", json=user_recipe_payload("x", product=product, product_name=name),
                    headers=users[who])
    data = client.get("/community/recipes/user-abc/choices").json()
    assert data["builds"] == 3
    top = data["ingredients"]["c"]
    assert [(c["product"]["id"], c["count"]) for c in top] == [("parmesan", 2), ("grana", 1)]
    assert client.get("/community/recipes/unknown/choices").json() == {"recipe_id": "unknown", "builds": 0,
                                                                      "ingredients": {}}
