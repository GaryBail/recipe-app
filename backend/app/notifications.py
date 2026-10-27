"""Уведомления: «вашу сборку оценили» / «оставили отзыв».

Уведомления всегда сохраняются на сервере (список в приложении).
Push через APNs отправляется, только если настроены ключи Apple (см. README).
"""

from __future__ import annotations

import logging
import sqlite3
import time
from datetime import datetime, timezone
from typing import Any, Protocol

from pydantic import BaseModel, Field

log = logging.getLogger(__name__)


class DeviceIn(BaseModel):
    token: str = Field(min_length=32, max_length=200, pattern="^[0-9a-fA-F]+$")


class MarkReadIn(BaseModel):
    ids: list[int] | None = None  # None — все


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def stars_text(stars: int) -> str:
    return "★" * stars + "☆" * (5 - stars)


def describe(kind: str, actor: str, build_name: str, stars: int | None, comment: str | None) -> tuple[str, str]:
    """Заголовок и текст уведомления."""
    if kind == "comment" and comment:
        short = comment if len(comment) <= 120 else comment[:117] + "…"
        return f"Новый отзыв на «{build_name}»", f"{actor}: {short}"
    return f"Новая оценка «{build_name}»", f"{actor} оценил(а) вашу сборку: {stars_text(stars or 0)}"


class NotificationStore:
    def __init__(self, db: sqlite3.Connection):
        self.db = db
        self.db.executescript("""
            CREATE TABLE IF NOT EXISTS notifications (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id TEXT NOT NULL,
                kind TEXT NOT NULL,
                build_id TEXT NOT NULL,
                build_name TEXT NOT NULL,
                actor_id TEXT NOT NULL,
                actor_name TEXT NOT NULL,
                stars INTEGER,
                comment TEXT,
                created_at TEXT NOT NULL,
                read_at TEXT
            );
            CREATE INDEX IF NOT EXISTS notifications_user ON notifications(user_id, id);
            CREATE TABLE IF NOT EXISTS devices (
                token TEXT PRIMARY KEY,
                user_id TEXT NOT NULL,
                created_at TEXT NOT NULL
            );
        """)
        self.db.commit()

    def add(self, user_id: str, kind: str, build_id: str, build_name: str,
            actor_id: str, actor_name: str, stars: int | None, comment: str | None) -> dict[str, Any]:
        cur = self.db.execute(
            "INSERT INTO notifications (user_id, kind, build_id, build_name, actor_id, actor_name,"
            " stars, comment, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (user_id, kind, build_id, build_name, actor_id, actor_name, stars, comment, _now()),
        )
        self.db.commit()
        return self._public(self.db.execute("SELECT * FROM notifications WHERE id = ?", (cur.lastrowid,)).fetchone())

    @staticmethod
    def _public(row: sqlite3.Row) -> dict[str, Any]:
        title, body = describe(row["kind"], row["actor_name"], row["build_name"], row["stars"], row["comment"])
        return {
            "id": row["id"], "kind": row["kind"], "build_id": row["build_id"], "build_name": row["build_name"],
            "actor_name": row["actor_name"], "stars": row["stars"], "comment": row["comment"],
            "title": title, "body": body, "created_at": row["created_at"], "is_read": row["read_at"] is not None,
        }

    def list(self, user_id: str, limit: int = 50) -> list[dict[str, Any]]:
        rows = self.db.execute(
            "SELECT * FROM notifications WHERE user_id = ?"
            " AND actor_id NOT IN (SELECT blocked_id FROM blocks WHERE user_id = ?)"
            " ORDER BY id DESC LIMIT ?",
            (user_id, user_id, limit),
        ).fetchall()
        return [self._public(r) for r in rows]

    def unread_count(self, user_id: str) -> int:
        return self.db.execute(
            "SELECT COUNT(*) FROM notifications WHERE user_id = ? AND read_at IS NULL"
            " AND actor_id NOT IN (SELECT blocked_id FROM blocks WHERE user_id = ?)",
            (user_id, user_id),
        ).fetchone()[0]

    def mark_read(self, user_id: str, ids: list[int] | None) -> None:
        if ids is None:
            self.db.execute("UPDATE notifications SET read_at = ? WHERE user_id = ? AND read_at IS NULL",
                            (_now(), user_id))
        elif ids:
            marks = ",".join("?" * len(ids))
            self.db.execute(f"UPDATE notifications SET read_at = ? WHERE user_id = ? AND id IN ({marks})",
                            (_now(), user_id, *ids))
        self.db.commit()

    # --- устройства для push ---

    def add_device(self, user_id: str, token: str) -> None:
        self.db.execute(
            "INSERT INTO devices (token, user_id, created_at) VALUES (?, ?, ?)"
            " ON CONFLICT(token) DO UPDATE SET user_id = excluded.user_id",
            (token.lower(), user_id, _now()),
        )
        self.db.commit()

    def remove_device(self, token: str) -> None:
        self.db.execute("DELETE FROM devices WHERE token = ?", (token.lower(),))
        self.db.commit()

    def devices(self, user_id: str) -> list[str]:
        return [r["token"] for r in self.db.execute("SELECT token FROM devices WHERE user_id = ?", (user_id,))]

    def delete_user(self, user_id: str) -> None:
        self.db.execute("DELETE FROM notifications WHERE user_id = ? OR actor_id = ?", (user_id, user_id))
        self.db.execute("DELETE FROM devices WHERE user_id = ?", (user_id,))
        self.db.commit()


# ---------- Push ----------

class PushSender(Protocol):
    async def send(self, tokens: list[str], title: str, body: str, badge: int, data: dict[str, Any]) -> list[str]:
        """Отправляет push; возвращает токены, которые больше не действительны."""
        ...


class NoopPush:
    async def send(self, tokens, title, body, badge, data) -> list[str]:
        return []


def apns_payload(title: str, body: str, badge: int, data: dict[str, Any]) -> dict[str, Any]:
    return {"aps": {"alert": {"title": title, "body": body}, "sound": "default", "badge": badge}, **data}


class APNsPush:
    """Отправка через Apple Push Notification service (HTTP/2, токен-аутентификация .p8)."""

    def __init__(self, key_path: str, key_id: str, team_id: str, topic: str, sandbox: bool = True):
        with open(key_path) as f:
            self._key = f.read()
        self.key_id, self.team_id, self.topic = key_id, team_id, topic
        self.host = "https://api.sandbox.push.apple.com" if sandbox else "https://api.push.apple.com"
        self._jwt: tuple[float, str] | None = None

    def _provider_token(self) -> str:
        import jwt

        # Apple принимает токен до часа; обновляем раз в 50 минут.
        if self._jwt is None or time.time() - self._jwt[0] > 50 * 60:
            token = jwt.encode({"iss": self.team_id, "iat": int(time.time())}, self._key,
                               algorithm="ES256", headers={"kid": self.key_id})
            self._jwt = (time.time(), token)
        return self._jwt[1]

    async def send(self, tokens, title, body, badge, data) -> list[str]:
        import httpx

        invalid: list[str] = []
        headers = {"authorization": f"bearer {self._provider_token()}", "apns-topic": self.topic,
                   "apns-push-type": "alert"}
        async with httpx.AsyncClient(http2=True, timeout=10) as client:
            for token in tokens:
                try:
                    r = await client.post(f"{self.host}/3/device/{token}", headers=headers,
                                          json=apns_payload(title, body, badge, data))
                except httpx.HTTPError:
                    log.exception("APNs request failed")
                    continue
                if r.status_code == 410 or (r.status_code == 400 and "BadDeviceToken" in r.text):
                    invalid.append(token)
                elif r.status_code != 200:
                    log.warning("APNs %s: %s", r.status_code, r.text)
        return invalid
