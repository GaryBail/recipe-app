import itertools
import json
import time

import jwt
from cryptography.hazmat.primitives.asymmetric import rsa
from fastapi.testclient import TestClient

from app.auth import AppleTokenVerifier
from app.main import create_app
from app.service import PriceService

BUNDLE_ID = "com.garybail.recipeapp"
_counter = itertools.count()


class FakeApple:
    """Свой RSA-ключ вместо ключей Apple."""

    def __init__(self):
        self.key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        jwk = json.loads(jwt.algorithms.RSAAlgorithm.to_jwk(self.key.public_key()))
        jwk["kid"] = "test-kid"
        self.verifier = AppleTokenVerifier(BUNDLE_ID, fetch_keys=lambda: {"keys": [jwk]})

    def token(self, sub="apple-user-1", email=None, aud=BUNDLE_ID, expires_in=600, iss="https://appleid.apple.com"):
        claims = {"iss": iss, "aud": aud, "sub": sub, "iat": int(time.time()),
                  "exp": int(time.time()) + expires_in}
        if email:
            claims["email"] = email
        return jwt.encode(claims, self.key, algorithm="RS256", headers={"kid": "test-kid"})


class RecordingMailer:
    def __init__(self):
        self.sent = []

    async def send(self, to, subject, text):
        self.sent.append({"to": to, "subject": subject, "text": text})

    def last_code(self, email):
        import re
        for mail in reversed(self.sent):
            if mail["to"] == email:
                return re.search(r"\b(\d{6})\b", mail["text"]).group(1)
        raise AssertionError(f"нет письма для {email}")


class FakeClock:
    def __init__(self, start=1_000_000.0):
        self.now = start

    def __call__(self):
        return self.now


class RecordingPush:
    def __init__(self):
        self.sent = []

    async def send(self, tokens, title, body, badge, data):
        self.sent.append({"tokens": tokens, "title": title, "body": body, "badge": badge, "data": data})
        return []


def make_client(tmp_path, adapters=(), apple=None, push=None, mailer=None, clock=None):
    mailer = mailer or RecordingMailer()
    app = create_app(PriceService(list(adapters)), db_path=str(tmp_path / "test.db"),
                     apple=(apple or FakeApple()).verifier, push=push or RecordingPush(),
                     mailer=mailer, limiter_clock=clock, price_watch=False,
                     media_dir=str(tmp_path / "media"))
    app.state.mailer = mailer
    return TestClient(app)


def register(client, name="Алиса", email=None, password="secret123", verify=True):
    email = email or f"user{next(_counter)}@example.com"
    r = client.post("/auth/register", json={"email": email, "password": password, "display_name": name})
    assert r.status_code == 201, r.text
    data = r.json()
    headers = {"Authorization": f"Bearer {data['token']}"}
    user = data["user"]
    if verify:
        code = client.app.state.mailer.last_code(email)
        r = client.post("/auth/verify-email", json={"code": code}, headers=headers)
        assert r.status_code == 200, r.text
        user = r.json()
    return headers, user


def build_payload():
    return {
        "name": "Карбонара",
        "recipe": {"id": "carbonara", "title": "Паста карбонара", "summary": "", "servings": 2, "steps": [],
                   "ingredients": [{"id": "c", "title": "Сыр", "category_id": "hc", "amount": 60, "unit": "g"}]},
        "items": [{"ingredient_id": "c", "product": {"id": "parmesan", "name": "Пармезан", "category_id": "hc"}}],
    }
