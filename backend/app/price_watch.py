"""Слежение за ценами сборок и ежедневные напоминания.

Как работает:
1. Пользователь включает «Следить за ценой» у сборки — приложение присылает её состав (подписка).
2. Несколько раз в день (по умолчанию 07:00, 12:00, 18:00 МСК) сервер собирает все уникальные
   товары из подписок и один раз ищет каждый в каждом магазине
   (Санкт-Петербург: Лента, Магнит, Ашан, ВкусВилл, Купер).
   Между запросами — пауза, чтобы не нагружать сайты.
3. Для каждой подписки считается стоимость корзины в каждом магазине; итог сохраняется в историю.
4. Уведомления — не чаще одного в день на пользователя и только днём:
   - если корзина заметно подешевела относительно обычной цены — «Подешевело»;
   - иначе, если давно ничего не присылали, — мягкое напоминание с текущей ценой.
   Выбирается одна сборка — с наибольшим снижением цены.

Запустить проверку вручную: python -m app.price_watch
"""

from __future__ import annotations

import asyncio
import json
import logging
import random
import sqlite3
import statistics
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from typing import Any, Callable

from pydantic import BaseModel, Field

from .matching import best_match
from .models import City, Offer
from .service import CITIES, PriceService

log = logging.getLogger(__name__)

MSK = timezone(timedelta(hours=3))  # московское время (и в Петербурге); перехода на летнее нет

WATCH_CITIES = {"spb"}  # приоритет — Петербург, где сильнее всего представлена Лента
MAX_WATCHES_PER_USER = 20
REFRESH_HOURS = (7, 12, 18)          # когда обновлять цены (МСК)
NOTIFY_WINDOW = (10, 21)             # когда можно присылать уведомления (МСК)
DROP_THRESHOLD = 0.05                # «подешевело» — от 5% ниже обычной цены
REMINDER_EVERY_DAYS = 3              # мягкое напоминание — не чаще раза в 3 дня
HISTORY_DAYS = 14                    # «обычная цена» — медиана за 2 недели


class WatchLineIn(BaseModel):
    product_id: str = Field(min_length=1, max_length=100)
    query: str = Field(min_length=2, max_length=150)
    required_amount: float = Field(gt=0, le=100_000)
    unit: str = Field(pattern="^(g|ml|pcs)$")


class WatchIn(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    recipe_title: str = Field(min_length=1, max_length=100)
    city_id: str = "spb"
    lines: list[WatchLineIn] = Field(min_length=1, max_length=50)


class TooManyWatches(Exception):
    pass


def _iso(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).isoformat(timespec="seconds")


def _kop(value: Decimal) -> int:
    return int((value * 100).to_integral_value())


def _rub(kop: int) -> str:
    return f"{kop / 100:,.0f}".replace(",", " ")


class WatchStore:
    def __init__(self, db: sqlite3.Connection):
        self.db = db
        self.db.executescript("""
            CREATE TABLE IF NOT EXISTS watches (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id TEXT NOT NULL,
                client_id TEXT NOT NULL,
                name TEXT NOT NULL,
                recipe_title TEXT NOT NULL,
                city_id TEXT NOT NULL,
                lines TEXT NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                UNIQUE (user_id, client_id)
            );
            CREATE TABLE IF NOT EXISTS search_snapshots (
                store_id TEXT NOT NULL,
                city_id TEXT NOT NULL,
                query TEXT NOT NULL,
                offers TEXT NOT NULL,
                fetched_at TEXT NOT NULL,
                PRIMARY KEY (store_id, city_id, query)
            );
            CREATE TABLE IF NOT EXISTS basket_history (
                watch_id INTEGER NOT NULL REFERENCES watches(id) ON DELETE CASCADE,
                store_id TEXT NOT NULL,
                total_kop INTEGER NOT NULL,
                complete INTEGER NOT NULL,
                missing INTEGER NOT NULL,
                computed_at TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS basket_history_watch ON basket_history(watch_id, computed_at);
            CREATE TABLE IF NOT EXISTS price_notices (
                user_id TEXT NOT NULL,
                kind TEXT NOT NULL,
                watch_id INTEGER,
                sent_at TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS price_notices_user ON price_notices(user_id, sent_at);
        """)
        self.db.commit()

    # --- подписки ---

    def upsert(self, user_id: str, client_id: str, data: WatchIn, now: datetime) -> dict[str, Any]:
        exists = self.db.execute("SELECT 1 FROM watches WHERE user_id = ? AND client_id = ?",
                                 (user_id, client_id)).fetchone()
        if not exists:
            count = self.db.execute("SELECT COUNT(*) FROM watches WHERE user_id = ?", (user_id,)).fetchone()[0]
            if count >= MAX_WATCHES_PER_USER:
                raise TooManyWatches()
        lines = json.dumps([l.model_dump() for l in data.lines], ensure_ascii=False)
        self.db.execute(
            "INSERT INTO watches (user_id, client_id, name, recipe_title, city_id, lines, created_at, updated_at)"
            " VALUES (?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(user_id, client_id) DO UPDATE SET"
            " name = excluded.name, recipe_title = excluded.recipe_title, city_id = excluded.city_id,"
            " lines = excluded.lines, updated_at = excluded.updated_at",
            (user_id, client_id, data.name, data.recipe_title, data.city_id, lines, _iso(now), _iso(now)),
        )
        # Состав изменился — старая история цен больше не сравнима.
        row = self._row(user_id, client_id)
        if exists:
            self.db.execute("DELETE FROM basket_history WHERE watch_id = ?", (row["id"],))
        self.db.commit()
        return self.public(row)

    def delete(self, user_id: str, client_id: str) -> bool:
        cur = self.db.execute("DELETE FROM watches WHERE user_id = ? AND client_id = ?", (user_id, client_id))
        self.db.commit()
        return cur.rowcount > 0

    def delete_user(self, user_id: str) -> None:
        self.db.execute("DELETE FROM watches WHERE user_id = ?", (user_id,))
        self.db.execute("DELETE FROM price_notices WHERE user_id = ?", (user_id,))
        self.db.commit()

    def _row(self, user_id: str, client_id: str) -> sqlite3.Row:
        return self.db.execute("SELECT * FROM watches WHERE user_id = ? AND client_id = ?",
                               (user_id, client_id)).fetchone()

    def get(self, user_id: str, client_id: str) -> dict[str, Any] | None:
        row = self._row(user_id, client_id)
        return self.public(row) if row else None

    def list(self, user_id: str) -> list[dict[str, Any]]:
        rows = self.db.execute("SELECT * FROM watches WHERE user_id = ? ORDER BY id", (user_id,)).fetchall()
        return [self.public(r) for r in rows]

    def all(self) -> list[sqlite3.Row]:
        return self.db.execute("SELECT * FROM watches").fetchall()

    def public(self, row: sqlite3.Row) -> dict[str, Any]:
        latest = self.latest_baskets(row["id"])
        best = min((b for b in latest if b["complete"]), key=lambda b: b["total_kop"], default=None)
        usual = self.usual_total(row["id"])
        return {
            "client_id": row["client_id"],
            "name": row["name"],
            "recipe_title": row["recipe_title"],
            "city_id": row["city_id"],
            "updated_at": row["updated_at"],
            "checked_at": latest[0]["computed_at"] if latest else None,
            "best": ({"store_id": best["store_id"], "total": f"{best['total_kop'] / 100:.2f}"} if best else None),
            "usual_total": f"{usual / 100:.2f}" if usual else None,
            "stores": [{"store_id": b["store_id"], "total": f"{b['total_kop'] / 100:.2f}",
                        "complete": bool(b["complete"]), "missing": b["missing"]} for b in latest],
        }

    # --- снимки цен ---

    def save_snapshot(self, store_id: str, city_id: str, query: str, offers: list[Offer], now: datetime) -> None:
        self.db.execute(
            "INSERT INTO search_snapshots (store_id, city_id, query, offers, fetched_at) VALUES (?, ?, ?, ?, ?)"
            " ON CONFLICT(store_id, city_id, query) DO UPDATE SET offers = excluded.offers,"
            " fetched_at = excluded.fetched_at",
            (store_id, city_id, query.lower(), json.dumps([o.to_json() for o in offers], ensure_ascii=False),
             _iso(now)),
        )
        self.db.commit()

    def snapshot(self, store_id: str, city_id: str, query: str) -> list[Offer] | None:
        row = self.db.execute("SELECT offers FROM search_snapshots WHERE store_id = ? AND city_id = ? AND query = ?",
                              (store_id, city_id, query.lower())).fetchone()
        if row is None:
            return None
        return [Offer(store_id=o["store_id"], sku=o["sku"], title=o["title"], price=Decimal(o["price"]),
                      package_amount=o["package_amount"], unit=o["unit"], in_stock=o["in_stock"],
                      is_weighted=o["is_weighted"],
                      regular_price=Decimal(o["regular_price"]) if o.get("regular_price") else None,
                      image_url=o.get("image_url"))
                for o in json.loads(row["offers"])]

    # --- история корзин ---

    def record_basket(self, watch_id: int, store_id: str, total: Decimal, complete: bool, missing: int,
                      now: datetime) -> None:
        self.db.execute(
            "INSERT INTO basket_history (watch_id, store_id, total_kop, complete, missing, computed_at)"
            " VALUES (?, ?, ?, ?, ?, ?)",
            (watch_id, store_id, _kop(total), int(complete), missing, _iso(now)),
        )
        self.db.commit()

    def latest_baskets(self, watch_id: int) -> list[sqlite3.Row]:
        return self.db.execute(
            "SELECT * FROM basket_history WHERE watch_id = ? AND computed_at ="
            " (SELECT MAX(computed_at) FROM basket_history WHERE watch_id = ?) ORDER BY total_kop",
            (watch_id, watch_id),
        ).fetchall()

    def cheapest_by_run(self, watch_id: int, since: datetime) -> list[tuple[str, int, str]]:
        """[(время, самая дешёвая полная корзина, магазин)] по запускам, от старых к новым."""
        rows = self.db.execute(
            "SELECT computed_at, store_id, total_kop FROM basket_history"
            " WHERE watch_id = ? AND complete = 1 AND computed_at >= ? ORDER BY computed_at, total_kop",
            (watch_id, _iso(since)),
        ).fetchall()
        result: dict[str, tuple[int, str]] = {}
        for r in rows:
            if r["computed_at"] not in result:
                result[r["computed_at"]] = (r["total_kop"], r["store_id"])
        return [(at, kop, store) for at, (kop, store) in sorted(result.items())]

    def usual_total(self, watch_id: int) -> int | None:
        runs = self.cheapest_by_run(watch_id, datetime.now(timezone.utc) - timedelta(days=HISTORY_DAYS))
        if len(runs) < 2:
            return None
        return int(statistics.median(kop for _, kop, _ in runs[:-1]))

    # --- журнал уведомлений о ценах ---

    def log_notice(self, user_id: str, kind: str, watch_id: int, now: datetime) -> None:
        self.db.execute("INSERT INTO price_notices (user_id, kind, watch_id, sent_at) VALUES (?, ?, ?, ?)",
                        (user_id, kind, watch_id, _iso(now)))
        self.db.commit()

    def last_notice(self, user_id: str) -> datetime | None:
        row = self.db.execute("SELECT MAX(sent_at) AS at FROM price_notices WHERE user_id = ?", (user_id,)).fetchone()
        return datetime.fromisoformat(row["at"]) if row and row["at"] else None


@dataclass
class Candidate:
    watch: sqlite3.Row
    current_kop: int
    store_id: str
    usual_kop: int | None

    @property
    def drop(self) -> float:
        if not self.usual_kop:
            return 0.0
        return (self.usual_kop - self.current_kop) / self.usual_kop


STORE_NAMES = {"lenta": "Ленте", "magnit": "Магните", "auchan": "Ашане", "vkusvill": "ВкусВилле",
               "kuper": "Купере"}  # «в …»


def price_message(c: Candidate) -> tuple[str, str, str]:
    """(вид, заголовок, текст)."""
    store = STORE_NAMES.get(c.store_id, c.store_id)
    name, recipe = c.watch["name"], c.watch["recipe_title"]
    if c.drop >= DROP_THRESHOLD:
        pct = round(c.drop * 100)
        return ("price_drop", f"Подешевело: {recipe}",
                f"Сборка «{name}» сейчас {_rub(c.current_kop)} ₽ в {store} — на {pct}% дешевле обычного.")
    return ("reminder", f"Что приготовить сегодня? {recipe}",
            f"Продукты для сборки «{name}» — от {_rub(c.current_kop)} ₽ в {store}. Загляните за рецептом!")


class PriceWatcher:
    def __init__(self, watches: WatchStore, prices: PriceService, notifications: Any, auth: Any, push: Any,
                 delay: tuple[float, float] = (2.0, 5.0), clock: Callable[[], datetime] | None = None):
        self.watches = watches
        self.prices = prices
        self.notifications = notifications
        self.auth = auth
        self.push = push
        self.delay = delay
        self.clock = clock or (lambda: datetime.now(timezone.utc))
        self._lock = asyncio.Lock()

    async def refresh_prices(self, now: datetime) -> dict[str, int]:
        """Обновляет снимки цен для всех товаров из подписок. Возвращает число запросов по магазинам."""
        queries: dict[str, set[str]] = {}
        for w in self.watches.all():
            if w["city_id"] not in WATCH_CITIES:
                continue
            for line in json.loads(w["lines"]):
                queries.setdefault(w["city_id"], set()).add(line["query"])

        stats: dict[str, int] = {}
        for city_id, qs in queries.items():
            city = next(c for c in CITIES if c.id == city_id)
            for store_id, adapter in self.prices.adapters.items():
                done = 0
                for q in sorted(qs):
                    try:
                        offers = await adapter.search(city, q)
                    except Exception:
                        log.exception("refresh failed: %s %r", store_id, q)
                        continue
                    self.watches.save_snapshot(store_id, city_id, q, offers, now)
                    # заодно освежаем кэш, из которого отвечает приложению /offers
                    self.prices._search_cache.put((store_id, city_id, q.strip().lower()), offers)
                    done += 1
                    if self.delay[1] > 0:
                        await asyncio.sleep(random.uniform(*self.delay))
                stats[store_id] = stats.get(store_id, 0) + done
        return stats

    def compute_baskets(self, now: datetime) -> int:
        count = 0
        for w in self.watches.all():
            if w["city_id"] not in WATCH_CITIES:
                continue
            lines = json.loads(w["lines"])
            for store_id in self.prices.adapters:
                total = Decimal(0)
                missing = 0
                known = False
                for line in lines:
                    offers = self.watches.snapshot(store_id, w["city_id"], line["query"])
                    if offers is None:
                        missing += 1
                        continue
                    known = True
                    match = best_match(line["query"], offers, line["required_amount"], line["unit"])
                    if match is None:
                        missing += 1
                    else:
                        total += match.cost
                if known:
                    self.watches.record_basket(w["id"], store_id, total, missing == 0, missing, now)
                    count += 1
        return count

    def _candidates(self, user_id: str, now: datetime) -> list[Candidate]:
        result = []
        for w in self.watches.db.execute("SELECT * FROM watches WHERE user_id = ?", (user_id,)):
            runs = self.watches.cheapest_by_run(w["id"], now - timedelta(days=HISTORY_DAYS))
            if not runs:
                continue
            _, current, store = runs[-1]
            usual = int(statistics.median(k for _, k, _ in runs[:-1])) if len(runs) >= 2 else None
            result.append(Candidate(watch=w, current_kop=current, store_id=store, usual_kop=usual))
        return result

    async def notify(self, now: datetime) -> list[dict[str, Any]]:
        local = now.astimezone(MSK)
        if not (NOTIFY_WINDOW[0] <= local.hour < NOTIFY_WINDOW[1]):
            return []
        sent = []
        user_ids = {r["user_id"] for r in self.watches.all()}
        for user_id in sorted(user_ids):
            user = self.auth.raw_user(user_id)
            if user is None or not user["price_alerts"]:
                continue
            last = self.watches.last_notice(user_id)
            if last is not None and last.astimezone(MSK).date() == local.date():
                continue  # не больше одного в день
            candidates = self._candidates(user_id, now)
            if not candidates:
                continue
            best = max(candidates, key=lambda c: (c.drop, -c.current_kop))
            if best.drop < DROP_THRESHOLD and last is not None and now - last < timedelta(days=REMINDER_EVERY_DAYS):
                continue  # цена обычная, а напоминали недавно
            kind, title, body = price_message(best)
            item = self.notifications.add(user_id, kind, best.watch["client_id"], best.watch["name"],
                                          "system", "ВыборВкуса", None, None, title=title, body=body)
            self.watches.log_notice(user_id, kind, best.watch["id"], now)
            tokens = self.notifications.devices(user_id)
            if tokens:
                try:
                    invalid = await self.push.send(tokens, title, body, self.notifications.unread_count(user_id),
                                                   {"kind": kind, "local_build_id": best.watch["client_id"]})
                    for t in invalid:
                        self.notifications.remove_device(t)
                except Exception:
                    log.exception("price push failed")
            sent.append(item)
        return sent

    async def run_once(self, notify: bool = True) -> dict[str, Any]:
        async with self._lock:
            now = self.clock()
            stats = await self.refresh_prices(now)
            baskets = self.compute_baskets(now)
            notices = await self.notify(now) if notify else []
            log.info("price watch: requests=%s baskets=%s notices=%s", stats, baskets, len(notices))
            return {"requests": stats, "baskets": baskets, "notifications": len(notices)}


def next_run(now: datetime, hours: tuple[int, ...] = REFRESH_HOURS) -> datetime:
    """Ближайшее время запуска (в МСК) строго после now."""
    local = now.astimezone(MSK)
    for day in range(2):
        date = (local + timedelta(days=day)).date()
        for h in sorted(hours):
            candidate = datetime(date.year, date.month, date.day, h, tzinfo=MSK)
            if candidate > local:
                return candidate
    raise RuntimeError("unreachable")


async def scheduler_loop(watcher: PriceWatcher, hours: tuple[int, ...] = REFRESH_HOURS) -> None:
    while True:
        target = next_run(datetime.now(timezone.utc), hours)
        await asyncio.sleep(max(1.0, (target - datetime.now(timezone.utc)).total_seconds()))
        try:
            await watcher.run_once()
        except Exception:
            log.exception("price watch run failed")


def hours_from_env(raw: str | None) -> tuple[int, ...]:
    if not raw:
        return REFRESH_HOURS
    hours = tuple(sorted({int(h) for h in raw.split(",") if h.strip()}))
    if not hours or any(h < 0 or h > 23 for h in hours):
        raise ValueError("PRICE_REFRESH_HOURS: часы 0–23 через запятую")
    return hours


if __name__ == "__main__":  # ручной запуск: python -m app.price_watch
    import os

    from .auth import AuthStore
    from .community import CommunityStore, open_db
    from .main import default_adapters, push_from_env
    from .notifications import NotificationStore

    logging.basicConfig(level=logging.INFO)

    async def _main() -> None:
        db = open_db(os.getenv("COMMUNITY_DB", "community.db"))
        CommunityStore(db)
        service = PriceService(default_adapters())
        watcher = PriceWatcher(WatchStore(db), service, NotificationStore(db), AuthStore(db), push_from_env())
        try:
            print(await watcher.run_once())
        finally:
            await service.close()

    asyncio.run(_main())
