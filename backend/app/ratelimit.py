"""Ограничение частоты действий (попытки входа, отправка кодов, регистрация).

События хранятся в SQLite, поэтому лимиты переживают перезапуск сервера.
"""

from __future__ import annotations

import math
import sqlite3
import time
from typing import Callable


class RateLimiter:
    def __init__(self, db: sqlite3.Connection, clock: Callable[[], float] = time.time):
        self.db = db
        self.clock = clock
        self.db.executescript("""
            CREATE TABLE IF NOT EXISTS rate_events (key TEXT NOT NULL, at REAL NOT NULL);
            CREATE INDEX IF NOT EXISTS rate_events_key ON rate_events(key, at);
        """)
        self.db.commit()

    def retry_after(self, key: str, limit: int, window: float) -> int:
        """0 — можно; иначе сколько секунд подождать."""
        since = self.clock() - window
        rows = self.db.execute("SELECT at FROM rate_events WHERE key = ? AND at > ? ORDER BY at",
                               (key, since)).fetchall()
        if len(rows) < limit:
            return 0
        oldest_relevant = rows[len(rows) - limit]["at"]
        return max(1, math.ceil(oldest_relevant + window - self.clock()))

    def hit(self, key: str) -> None:
        self.db.execute("INSERT INTO rate_events (key, at) VALUES (?, ?)", (key, self.clock()))
        self.db.commit()

    def clear(self, key: str) -> None:
        self.db.execute("DELETE FROM rate_events WHERE key = ?", (key,))
        self.db.commit()

    def cleanup(self, older_than: float = 24 * 3600) -> None:
        self.db.execute("DELETE FROM rate_events WHERE at < ?", (self.clock() - older_than,))
        self.db.commit()


def wait_text(seconds: int) -> str:
    minutes = max(1, math.ceil(seconds / 60))
    return f"Слишком много попыток. Попробуйте через {minutes} мин."
