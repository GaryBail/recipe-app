"""Аккаунты: регистрация по email и паролю, вход через Apple, сессии, удаление аккаунта.

- Пароли хэшируются scrypt (стандартная библиотека) с солью.
- Сессия — случайный токен; в базе хранится только его SHA-256.
- Вход через Apple: приложение присылает identity token, сервер проверяет подпись
  по открытым ключам Apple, издателя, аудиторию (bundle id) и срок действия.
"""

from __future__ import annotations

import hashlib
import hmac
import json
import re
import secrets
import sqlite3
import time
import urllib.request
import uuid
from datetime import datetime, timezone
from typing import Any, Callable

from pydantic import BaseModel, Field, field_validator

EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


# ---------- Входные данные ----------

class RegisterIn(BaseModel):
    email: str = Field(max_length=254)
    password: str = Field(min_length=8, max_length=128)
    display_name: str = Field(min_length=1, max_length=50)
    city_id: str | None = Field(default=None, max_length=20)

    @field_validator("email")
    @classmethod
    def valid_email(cls, v: str) -> str:
        v = v.strip().lower()
        if not EMAIL_RE.match(v):
            raise ValueError("Некорректный email")
        return v

    @field_validator("display_name")
    @classmethod
    def strip_name(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("Имя не может быть пустым")
        return v

    @field_validator("password")
    @classmethod
    def strong_enough(cls, v: str) -> str:
        if not (re.search(r"[A-Za-zА-Яа-я]", v) and re.search(r"\d", v)):
            raise ValueError("Пароль должен содержать буквы и цифры")
        return v


class LoginIn(BaseModel):
    email: str
    password: str


class AppleLoginIn(BaseModel):
    identity_token: str = Field(min_length=10)
    # Apple отдаёт имя только при первом входе — приложение передаёт его, если получило.
    display_name: str | None = Field(default=None, max_length=50)


class ProfileUpdateIn(BaseModel):
    display_name: str | None = Field(default=None, min_length=1, max_length=50)
    city_id: str | None = Field(default=None, max_length=20)


# ---------- Пароли ----------

_SCRYPT = {"n": 2**14, "r": 8, "p": 1, "dklen": 32}


def hash_password(password: str) -> str:
    salt = secrets.token_bytes(16)
    digest = hashlib.scrypt(password.encode(), salt=salt, **_SCRYPT)
    return f"scrypt${salt.hex()}${digest.hex()}"


def verify_password(password: str, stored: str | None) -> bool:
    if not stored or not stored.startswith("scrypt$"):
        return False
    _, salt_hex, digest_hex = stored.split("$")
    digest = hashlib.scrypt(password.encode(), salt=bytes.fromhex(salt_hex), **_SCRYPT)
    return hmac.compare_digest(digest.hex(), digest_hex)


def _token_hash(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


class EmailTaken(Exception):
    pass


# ---------- Хранилище ----------

class AuthStore:
    def __init__(self, db: sqlite3.Connection):
        self.db = db
        self.db.executescript("""
            CREATE TABLE IF NOT EXISTS users (
                id TEXT PRIMARY KEY,
                email TEXT UNIQUE,
                password_hash TEXT,
                apple_sub TEXT UNIQUE,
                display_name TEXT NOT NULL,
                city_id TEXT,
                created_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS sessions (
                token_hash TEXT PRIMARY KEY,
                user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                created_at TEXT NOT NULL
            );
        """)
        self.db.commit()

    @staticmethod
    def public(row: sqlite3.Row | dict) -> dict[str, Any]:
        return {
            "id": row["id"],
            "email": row["email"],
            "display_name": row["display_name"],
            "city_id": row["city_id"],
            "has_apple": row["apple_sub"] is not None,
            "has_password": row["password_hash"] is not None,
            "created_at": row["created_at"],
        }

    def _user(self, user_id: str) -> sqlite3.Row:
        return self.db.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()

    def _new_session(self, user_id: str) -> str:
        token = secrets.token_urlsafe(32)
        self.db.execute("INSERT INTO sessions (token_hash, user_id, created_at) VALUES (?, ?, ?)",
                        (_token_hash(token), user_id, _now()))
        self.db.commit()
        return token

    def register(self, data: RegisterIn) -> tuple[dict[str, Any], str]:
        user_id = uuid.uuid4().hex
        try:
            self.db.execute(
                "INSERT INTO users (id, email, password_hash, display_name, city_id, created_at)"
                " VALUES (?, ?, ?, ?, ?, ?)",
                (user_id, data.email, hash_password(data.password), data.display_name, data.city_id, _now()),
            )
        except sqlite3.IntegrityError as e:
            raise EmailTaken() from e
        return self.public(self._user(user_id)), self._new_session(user_id)

    def login(self, email: str, password: str) -> tuple[dict[str, Any], str] | None:
        row = self.db.execute("SELECT * FROM users WHERE email = ?", (email.strip().lower(),)).fetchone()
        if row is None:
            hash_password(password)  # одинаковое время ответа, чтобы не выдавать, есть ли email
            return None
        if not verify_password(password, row["password_hash"]):
            return None
        return self.public(row), self._new_session(row["id"])

    def apple_login(self, sub: str, email: str | None, display_name: str | None) -> tuple[dict[str, Any], str, bool]:
        """Возвращает (пользователь, токен, создан ли новый аккаунт)."""
        row = self.db.execute("SELECT * FROM users WHERE apple_sub = ?", (sub,)).fetchone()
        created = False
        if row is None:
            # Не привязываем автоматически к аккаунту с тем же email: email при регистрации
            # не подтверждается, и иначе можно заранее «занять» чужой аккаунт.
            email = email.lower() if email else None
            taken = email is not None and self.db.execute(
                "SELECT 1 FROM users WHERE email = ?", (email,)).fetchone() is not None
            user_id = uuid.uuid4().hex
            name = (display_name or "").strip() or "Пользователь"
            self.db.execute(
                "INSERT INTO users (id, email, apple_sub, display_name, created_at) VALUES (?, ?, ?, ?, ?)",
                (user_id, None if taken else email, sub, name, _now()),
            )
            created = True
            self.db.commit()
            row = self._user(user_id)
        return self.public(row), self._new_session(row["id"]), created

    def user_for_token(self, token: str) -> dict[str, Any] | None:
        row = self.db.execute(
            "SELECT u.* FROM sessions s JOIN users u ON u.id = s.user_id WHERE s.token_hash = ?",
            (_token_hash(token),),
        ).fetchone()
        return self.public(row) if row else None

    def logout(self, token: str) -> None:
        self.db.execute("DELETE FROM sessions WHERE token_hash = ?", (_token_hash(token),))
        self.db.commit()

    def update(self, user_id: str, data: ProfileUpdateIn) -> dict[str, Any]:
        if data.display_name is not None:
            self.db.execute("UPDATE users SET display_name = ? WHERE id = ?", (data.display_name.strip(), user_id))
        if data.city_id is not None:
            self.db.execute("UPDATE users SET city_id = ? WHERE id = ?", (data.city_id or None, user_id))
        self.db.commit()
        return self.public(self._user(user_id))

    def delete(self, user_id: str) -> None:
        self.db.execute("DELETE FROM sessions WHERE user_id = ?", (user_id,))
        self.db.execute("DELETE FROM users WHERE id = ?", (user_id,))
        self.db.commit()


# ---------- Sign in with Apple ----------

class AppleTokenError(Exception):
    pass


def _fetch_apple_keys() -> dict[str, Any]:
    with urllib.request.urlopen(AppleTokenVerifier.KEYS_URL, timeout=10) as resp:
        return json.load(resp)


class AppleTokenVerifier:
    ISSUER = "https://appleid.apple.com"
    KEYS_URL = "https://appleid.apple.com/auth/keys"
    KEYS_TTL = 24 * 3600

    def __init__(self, audience: str, fetch_keys: Callable[[], dict[str, Any]] = _fetch_apple_keys):
        self.audience = audience
        self._fetch = fetch_keys
        self._keys: dict[str, Any] = {}
        self._fetched_at = 0.0

    def _key(self, kid: str) -> Any:
        import jwt

        stale = time.monotonic() - self._fetched_at > self.KEYS_TTL
        if stale or kid not in self._keys:  # Apple периодически меняет ключи
            self._keys = {k["kid"]: k for k in self._fetch().get("keys", [])}
            self._fetched_at = time.monotonic()
        jwk = self._keys.get(kid)
        if jwk is None:
            raise AppleTokenError("Неизвестный ключ подписи")
        return jwt.algorithms.RSAAlgorithm.from_jwk(json.dumps(jwk))

    def verify(self, identity_token: str) -> dict[str, Any]:
        import jwt

        try:
            kid = jwt.get_unverified_header(identity_token).get("kid", "")
            claims = jwt.decode(identity_token, self._key(kid), algorithms=["RS256"],
                                audience=self.audience, issuer=self.ISSUER)
        except AppleTokenError:
            raise
        except jwt.PyJWTError as e:
            raise AppleTokenError(str(e)) from e
        if not claims.get("sub"):
            raise AppleTokenError("Нет идентификатора пользователя")
        return claims
