import pytest

from app.notifications import apns_payload, describe
from tests.helpers import RecordingPush, build_payload as _build, make_client, register

DEVICE = "a" * 64


@pytest.fixture
def push():
    return RecordingPush()


@pytest.fixture
def client(tmp_path, push):
    with make_client(tmp_path, push=push) as c:
        yield c


def test_rating_and_comment_notify_author(client, push):
    alice, _ = register(client, name="Алиса")
    bob, _ = register(client, name="Боб")
    assert client.post("/devices", json={"token": DEVICE}, headers=alice).status_code == 204
    build = client.post("/community/builds", json=_build(), headers=alice).json()

    client.put(f"/community/builds/{build['id']}/rating", json={"stars": 4}, headers=bob)
    client.put(f"/community/builds/{build['id']}/rating", json={"stars": 5, "comment": "Очень вкусно!"}, headers=bob)

    data = client.get("/notifications", headers=alice).json()
    assert data["unread_count"] == 2
    comment, rating = data["items"]
    assert comment["kind"] == "comment" and comment["body"] == "Боб: Очень вкусно!"
    assert comment["title"] == "Новый отзыв на «Карбонара»"
    assert rating["kind"] == "rating" and "★★★★☆" in rating["body"]
    assert rating["build_id"] == build["id"]

    # push ушёл на устройство автора, с числом непрочитанных на значке
    assert len(push.sent) == 2
    assert push.sent[0]["tokens"] == [DEVICE]
    assert push.sent[1]["badge"] == 2
    assert push.sent[1]["data"] == {"build_id": build["id"], "kind": "comment"}

    # оценщику ничего не приходит
    assert client.get("/notifications", headers=bob).json()["items"] == []


def test_mark_read(client):
    alice, _ = register(client)
    bob, _ = register(client)
    build = client.post("/community/builds", json=_build(), headers=alice).json()
    client.put(f"/community/builds/{build['id']}/rating", json={"stars": 3}, headers=bob)
    client.put(f"/community/builds/{build['id']}/rating", json={"stars": 4}, headers=bob)

    first_id = client.get("/notifications", headers=alice).json()["items"][0]["id"]
    client.post("/notifications/read", json={"ids": [first_id]}, headers=alice)
    assert client.get("/notifications", headers=alice).json()["unread_count"] == 1
    client.post("/notifications/read", json={}, headers=alice)
    assert client.get("/notifications", headers=alice).json()["unread_count"] == 0


def test_blocked_users_do_not_notify(client):
    alice, _ = register(client)
    bob, bob_user = register(client)
    build = client.post("/community/builds", json=_build(), headers=alice).json()
    client.post("/community/blocks", json={"user_id": bob_user["id"]}, headers=alice)
    client.put(f"/community/builds/{build['id']}/rating", json={"stars": 1}, headers=bob)
    assert client.get("/notifications", headers=alice).json()["unread_count"] == 0


def test_device_validation(client):
    alice, _ = register(client)
    assert client.post("/devices", json={"token": "not-hex!"}, headers=alice).status_code == 422
    assert client.post("/devices", json={"token": DEVICE}).status_code == 401


def test_texts_and_payload():
    assert describe("rating", "Боб", "Салат", 5, None) == ("Новая оценка «Салат»", "Боб оценил(а) вашу сборку: ★★★★★")
    title, body = describe("comment", "Боб", "Салат", 4, "x" * 200)
    assert len(body) < 130 and body.endswith("…")
    payload = apns_payload("T", "B", 3, {"build_id": "1"})
    assert payload["aps"]["badge"] == 3 and payload["build_id"] == "1"
