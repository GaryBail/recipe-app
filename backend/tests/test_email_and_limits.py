import pytest

from tests.helpers import FakeClock, RecordingMailer, build_payload, make_client, register


@pytest.fixture
def mailer():
    return RecordingMailer()


@pytest.fixture
def clock():
    return FakeClock()


@pytest.fixture
def client(tmp_path, mailer, clock):
    with make_client(tmp_path, mailer=mailer, clock=clock) as c:
        yield c


# ---------- подтверждение email ----------

def test_register_sends_code_and_verifies(client, mailer):
    headers, user = register(client, email="new@example.com", verify=False)
    assert user["email_verified"] is False
    assert mailer.sent[-1]["to"] == "new@example.com"
    assert "код подтверждения" in mailer.sent[-1]["text"]

    code = mailer.last_code("new@example.com")
    wrong = "111111" if code != "111111" else "222222"
    assert client.post("/auth/verify-email", json={"code": wrong}, headers=headers).status_code == 400
    r = client.post("/auth/verify-email", json={"code": code}, headers=headers)
    assert r.status_code == 200 and r.json()["email_verified"] is True


def test_unverified_cannot_publish_or_rate(client):
    unverified, _ = register(client, verify=False)
    assert client.post("/community/builds", json=build_payload(), headers=unverified).status_code == 403

    author, _ = register(client)
    build = client.post("/community/builds", json=build_payload(), headers=author).json()
    r = client.put(f"/community/builds/{build['id']}/rating", json={"stars": 5}, headers=unverified)
    assert r.status_code == 403
    assert "Подтвердите email" in r.json()["detail"]


def test_resend_has_cooldown(client, mailer):
    headers, _ = register(client, email="slow@example.com", verify=False)
    # код только что отправлен при регистрации
    assert client.post("/auth/verify-email/send", headers=headers).status_code == 429


def test_wrong_codes_burn_the_code(client, mailer):
    headers, _ = register(client, email="brute@example.com", verify=False)
    code = mailer.last_code("brute@example.com")
    wrong = "111111" if code != "111111" else "222222"
    for _ in range(5):
        assert client.post("/auth/verify-email", json={"code": wrong}, headers=headers).status_code == 400
    # после 5 ошибок даже верный код не принимается
    assert client.post("/auth/verify-email", json={"code": code}, headers=headers).status_code == 400


def test_apple_accounts_are_verified(tmp_path):
    from tests.helpers import FakeApple
    apple = FakeApple()
    with make_client(tmp_path, apple=apple) as c:
        r = c.post("/auth/apple", json={"identity_token": apple.token(email="x@privaterelay.appleid.com")})
        assert r.json()["user"]["email_verified"] is True
        headers = {"Authorization": f"Bearer {r.json()['token']}"}
        assert c.post("/community/builds", json=build_payload(), headers=headers).status_code == 201


# ---------- восстановление и смена пароля ----------

def test_password_reset_flow(client, mailer):
    old_headers, _ = register(client, email="forgot@example.com")
    assert client.post("/auth/password/forgot", json={"email": "forgot@example.com"}).status_code == 204
    mail = mailer.sent[-1]
    assert mail["subject"] == "Код для восстановления пароля"
    code = mailer.last_code("forgot@example.com")

    wrong = "111111" if code != "111111" else "222222"
    bad = client.post("/auth/password/reset",
                      json={"email": "forgot@example.com", "code": wrong, "new_password": "newpass123"})
    assert bad.status_code == 400

    r = client.post("/auth/password/reset",
                    json={"email": "forgot@example.com", "code": code, "new_password": "newpass123"})
    assert r.status_code == 200, r.text
    assert r.json()["token"]

    # старые сессии закрыты, старый пароль не подходит, новый подходит
    assert client.get("/auth/me", headers=old_headers).status_code == 401
    assert client.post("/auth/login", json={"email": "forgot@example.com", "password": "secret123"}).status_code == 401
    assert client.post("/auth/login", json={"email": "forgot@example.com", "password": "newpass123"}).status_code == 200


def test_forgot_does_not_reveal_unknown_email(client, mailer):
    before = len(mailer.sent)
    assert client.post("/auth/password/forgot", json={"email": "nobody@example.com"}).status_code == 204
    assert len(mailer.sent) == before


def test_reset_rejects_weak_password(client, mailer):
    register(client, email="weak@example.com")
    client.post("/auth/password/forgot", json={"email": "weak@example.com"})
    code = mailer.last_code("weak@example.com")
    r = client.post("/auth/password/reset", json={"email": "weak@example.com", "code": code, "new_password": "short"})
    assert r.status_code == 422


def test_change_password(client):
    headers, _ = register(client, email="change@example.com")
    bad = client.post("/auth/password/change", json={"old_password": "wrong1234", "new_password": "another123"},
                      headers=headers)
    assert bad.status_code == 400
    r = client.post("/auth/password/change", json={"old_password": "secret123", "new_password": "another123"},
                    headers=headers)
    assert r.status_code == 200
    new_headers = {"Authorization": f"Bearer {r.json()['token']}"}
    assert client.get("/auth/me", headers=headers).status_code == 401
    assert client.get("/auth/me", headers=new_headers).status_code == 200


# ---------- ограничение попыток ----------

def test_login_lockout_after_five_failures(client, clock):
    register(client, email="lock@example.com")
    for _ in range(5):
        r = client.post("/auth/login", json={"email": "lock@example.com", "password": "wrong1234"})
        assert r.status_code == 401
    r = client.post("/auth/login", json={"email": "lock@example.com", "password": "secret123"})
    assert r.status_code == 429
    assert "Попробуйте через" in r.json()["detail"]
    assert int(r.headers["Retry-After"]) > 0

    clock.now += 15 * 60 + 1  # через 15 минут блокировка снимается
    assert client.post("/auth/login", json={"email": "lock@example.com", "password": "secret123"}).status_code == 200


def test_successful_login_resets_counter(client):
    register(client, email="reset-counter@example.com")
    for _ in range(4):
        client.post("/auth/login", json={"email": "reset-counter@example.com", "password": "wrong1234"})
    assert client.post("/auth/login", json={"email": "reset-counter@example.com",
                                            "password": "secret123"}).status_code == 200
    for _ in range(4):
        client.post("/auth/login", json={"email": "reset-counter@example.com", "password": "wrong1234"})
    assert client.post("/auth/login", json={"email": "reset-counter@example.com",
                                            "password": "secret123"}).status_code == 200


def test_register_limit_per_ip(client):
    for _ in range(10):
        register(client, verify=False)
    r = client.post("/auth/register", json={"email": "eleven@example.com", "password": "secret123",
                                            "display_name": "X"})
    assert r.status_code == 429
