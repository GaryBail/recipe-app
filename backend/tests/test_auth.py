import pytest

from app.auth import hash_password, verify_password
from tests.helpers import FakeApple, build_payload as _build, make_client, register


@pytest.fixture
def apple():
    return FakeApple()


@pytest.fixture
def client(tmp_path, apple):
    with make_client(tmp_path, apple=apple) as c:
        yield c


def test_password_hashing():
    stored = hash_password("secret123")
    assert stored.startswith("scrypt$") and "secret123" not in stored
    assert verify_password("secret123", stored)
    assert not verify_password("secret124", stored)
    assert not verify_password("secret123", None)


def test_register_login_me(client):
    r = client.post("/auth/register", json={"email": "  Alice@Example.com ", "password": "secret123",
                                            "display_name": " Алиса ", "city_id": "msk"})
    assert r.status_code == 201
    body = r.json()
    assert body["user"]["email"] == "alice@example.com"
    assert body["user"]["display_name"] == "Алиса"
    assert body["user"]["city_id"] == "msk"
    assert body["user"]["has_password"] and not body["user"]["has_apple"]

    me = client.get("/auth/me", headers={"Authorization": f"Bearer {body['token']}"})
    assert me.json()["id"] == body["user"]["id"]

    login = client.post("/auth/login", json={"email": "ALICE@example.com", "password": "secret123"})
    assert login.status_code == 200 and login.json()["token"] != body["token"]


@pytest.mark.parametrize("payload, code", [
    ({"email": "not-an-email", "password": "secret123", "display_name": "A"}, 422),
    ({"email": "a@b.ru", "password": "short1", "display_name": "A"}, 422),
    ({"email": "a@b.ru", "password": "onlyletters", "display_name": "A"}, 422),
    ({"email": "a@b.ru", "password": "secret123", "display_name": "   "}, 422),
])
def test_register_validation(client, payload, code):
    assert client.post("/auth/register", json=payload).status_code == code


def test_duplicate_email_and_wrong_password(client):
    register(client, email="dup@example.com")
    r = client.post("/auth/register", json={"email": "dup@example.com", "password": "secret123", "display_name": "B"})
    assert r.status_code == 409
    assert client.post("/auth/login", json={"email": "dup@example.com", "password": "wrong123"}).status_code == 401
    assert client.post("/auth/login", json={"email": "none@example.com", "password": "secret123"}).status_code == 401


def test_protected_endpoints_need_token(client):
    assert client.get("/auth/me").status_code == 401
    assert client.get("/auth/me", headers={"Authorization": "Bearer nope"}).status_code == 401


def test_logout_invalidates_token(client):
    headers, _ = register(client)
    assert client.post("/auth/logout", headers=headers).status_code == 204
    assert client.get("/auth/me", headers=headers).status_code == 401


def test_update_profile_renames_published_content(client):
    headers, _ = register(client, name="Старое имя")
    client.post("/community/builds", json=_build(), headers=headers)
    r = client.patch("/auth/me", json={"display_name": "Новое имя"}, headers=headers)
    assert r.json()["display_name"] == "Новое имя"
    assert client.get("/community/builds").json()[0]["author_name"] == "Новое имя"


def test_apple_sign_in_creates_then_reuses_account(client, apple):
    r = client.post("/auth/apple", json={"identity_token": apple.token(email="a@privaterelay.appleid.com"),
                                         "display_name": "Мария"})
    assert r.status_code == 200, r.text
    first = r.json()
    assert first["created"] is True
    assert first["user"]["display_name"] == "Мария"
    assert first["user"]["has_apple"] is True

    # повторный вход: Apple уже не присылает имя, аккаунт тот же
    again = client.post("/auth/apple", json={"identity_token": apple.token()}).json()
    assert again["created"] is False
    assert again["user"]["id"] == first["user"]["id"]
    assert again["user"]["display_name"] == "Мария"


def test_apple_does_not_take_over_password_account(client, apple):
    _, victim = register(client, email="victim@example.com")
    r = client.post("/auth/apple", json={"identity_token": apple.token(sub="attacker", email="victim@example.com")})
    assert r.json()["user"]["id"] != victim["id"]
    assert r.json()["user"]["email"] is None


@pytest.mark.parametrize("kwargs", [
    {"aud": "com.other.app"},
    {"iss": "https://evil.example.com"},
    {"expires_in": -60},
])
def test_apple_rejects_bad_tokens(client, apple, kwargs):
    assert client.post("/auth/apple", json={"identity_token": apple.token(**kwargs)}).status_code == 401


def test_apple_rejects_foreign_signature(client):
    other = FakeApple()  # другой ключ, тот же kid
    assert client.post("/auth/apple", json={"identity_token": other.token()}).status_code == 401


def test_delete_account_removes_content(client):
    alice, _ = register(client, name="Алиса")
    bob, _ = register(client, name="Боб")
    build = client.post("/community/builds", json=_build(), headers=alice).json()
    client.put(f"/community/builds/{build['id']}/rating", json={"stars": 5}, headers=bob)

    assert client.delete("/auth/me", headers=alice).status_code == 204
    assert client.get("/auth/me", headers=alice).status_code == 401
    assert client.get("/community/builds").json() == []
    assert client.get("/notifications", headers=bob).json()["items"] == []

