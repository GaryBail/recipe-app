"""Сообщество: публикация сборок, оценки, жалобы, блокировки, рекомендации.

Хранилище — SQLite (стандартная библиотека). Автор и имя берутся из аккаунта
пользователя (см. auth.py), а не из тела запроса.
"""

from __future__ import annotations

import json
import sqlite3
import uuid
from datetime import datetime, timezone
from typing import Any

from pydantic import BaseModel, Field, model_validator

# Сколько жалоб от разных пользователей скрывают сборку до проверки модератором.
HIDE_AFTER_REPORTS = 3

# Байесовское сглаживание рейтинга: новая сборка с одной пятёркой
# не должна обгонять сборку с сотней оценок 4.8.
PRIOR_MEAN = 3.5
PRIOR_WEIGHT = 3


# ---------- Входные данные ----------

class IngredientIn(BaseModel):
    id: str = Field(min_length=1, max_length=100)
    title: str = Field(min_length=1, max_length=100)
    category_id: str = Field(min_length=1, max_length=100)
    amount: float = Field(gt=0, le=100_000)
    unit: str = Field(pattern="^(g|ml|pcs)$")


class RecipeIn(BaseModel):
    id: str = Field(min_length=1, max_length=100)
    title: str = Field(min_length=1, max_length=100)
    summary: str = Field(default="", max_length=500)
    servings: int = Field(ge=1, le=100)
    steps: list[str] = Field(default_factory=list, max_length=50)
    ingredients: list[IngredientIn] = Field(min_length=1, max_length=50)
    # Необязательные поля своих рецептов (появились позже — старые клиенты их не присылают).
    rubric: str | None = Field(default=None, max_length=30)
    cook_minutes: int | None = Field(default=None, ge=0, le=24 * 60)


class ProductIn(BaseModel):
    id: str = Field(min_length=1, max_length=100)
    name: str = Field(min_length=1, max_length=150)
    brand: str | None = Field(default=None, max_length=100)
    category_id: str = Field(min_length=1, max_length=100)
    barcode: str | None = Field(default=None, max_length=50)


class ItemIn(BaseModel):
    ingredient_id: str
    product: ProductIn


class PublishIn(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    recipe: RecipeIn
    items: list[ItemIn] = Field(min_length=1, max_length=50)

    @model_validator(mode="after")
    def items_match_recipe(self) -> "PublishIn":
        ingredient_ids = {i.id for i in self.recipe.ingredients}
        for item in self.items:
            if item.ingredient_id not in ingredient_ids:
                raise ValueError(f"Ингредиента {item.ingredient_id} нет в рецепте")
        if len({i.ingredient_id for i in self.items}) != len(self.items):
            raise ValueError("Ингредиент указан в сборке дважды")
        return self


class RatingIn(BaseModel):
    stars: int = Field(ge=1, le=5)
    comment: str | None = Field(default=None, max_length=500)


class ReportIn(BaseModel):
    reason: str = Field(min_length=1, max_length=300)


class BlockIn(BaseModel):
    user_id: str


# ---------- Хранилище ----------

def bayesian_score(avg: float | None, count: int) -> float:
    total = (avg or 0) * count
    return (PRIOR_MEAN * PRIOR_WEIGHT + total) / (PRIOR_WEIGHT + count)


def open_db(path: str) -> sqlite3.Connection:
    db = sqlite3.connect(path, check_same_thread=False)
    db.row_factory = sqlite3.Row
    db.execute("PRAGMA foreign_keys = ON")
    return db


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


class CommunityStore:
    def __init__(self, db: sqlite3.Connection):
        self.db = db
        self.db.executescript("""
            PRAGMA foreign_keys = ON;
            CREATE TABLE IF NOT EXISTS builds (
                id TEXT PRIMARY KEY,
                author_id TEXT NOT NULL,
                author_name TEXT NOT NULL,
                recipe_id TEXT NOT NULL,
                name TEXT NOT NULL,
                payload TEXT NOT NULL,
                created_at TEXT NOT NULL,
                hidden INTEGER NOT NULL DEFAULT 0
            );
            CREATE INDEX IF NOT EXISTS builds_recipe ON builds(recipe_id);
            CREATE TABLE IF NOT EXISTS ratings (
                build_id TEXT NOT NULL REFERENCES builds(id) ON DELETE CASCADE,
                user_id TEXT NOT NULL,
                author_name TEXT NOT NULL,
                stars INTEGER NOT NULL,
                comment TEXT,
                created_at TEXT NOT NULL,
                PRIMARY KEY (build_id, user_id)
            );
            CREATE TABLE IF NOT EXISTS reports (
                build_id TEXT NOT NULL REFERENCES builds(id) ON DELETE CASCADE,
                user_id TEXT NOT NULL,
                reason TEXT NOT NULL,
                created_at TEXT NOT NULL,
                PRIMARY KEY (build_id, user_id)
            );
            CREATE TABLE IF NOT EXISTS blocks (
                user_id TEXT NOT NULL,
                blocked_id TEXT NOT NULL,
                PRIMARY KEY (user_id, blocked_id)
            );
        """)
        self.db.commit()

    def rename_user(self, user_id: str, name: str) -> None:
        """Пользователь сменил имя — обновляем подпись под его сборками и отзывами."""
        self.db.execute("UPDATE builds SET author_name = ? WHERE author_id = ?", (name, user_id))
        self.db.execute("UPDATE ratings SET author_name = ? WHERE user_id = ?", (name, user_id))
        self.db.commit()

    def delete_user_content(self, user_id: str) -> None:
        """Удаление аккаунта: сборки (с их оценками и жалобами), оценки, жалобы и блокировки пользователя."""
        self.db.execute("DELETE FROM builds WHERE author_id = ?", (user_id,))
        self.db.execute("DELETE FROM ratings WHERE user_id = ?", (user_id,))
        self.db.execute("DELETE FROM reports WHERE user_id = ?", (user_id,))
        self.db.execute("DELETE FROM blocks WHERE user_id = ? OR blocked_id = ?", (user_id, user_id))
        self.db.commit()

    # --- сборки ---

    def publish(self, user_id: str, author_name: str, data: PublishIn) -> dict[str, Any]:
        build_id = uuid.uuid4().hex
        payload = {"recipe": data.recipe.model_dump(), "items": [i.model_dump() for i in data.items]}
        self.db.execute(
            "INSERT INTO builds (id, author_id, author_name, recipe_id, name, payload, created_at)"
            " VALUES (?, ?, ?, ?, ?, ?, ?)",
            (build_id, user_id, author_name, data.recipe.id, data.name,
             json.dumps(payload, ensure_ascii=False), _now()),
        )
        self.db.commit()
        return self.get(build_id, user_id)  # type: ignore[return-value]

    def delete(self, build_id: str, user_id: str) -> bool:
        cur = self.db.execute("DELETE FROM builds WHERE id = ? AND author_id = ?", (build_id, user_id))
        self.db.commit()
        return cur.rowcount > 0

    _SELECT = """
        SELECT b.*, AVG(r.stars) AS rating_avg, COUNT(r.stars) AS rating_count,
               (SELECT stars FROM ratings WHERE build_id = b.id AND user_id = :me) AS my_rating
        FROM builds b LEFT JOIN ratings r ON r.build_id = b.id
        WHERE b.hidden = 0
          AND b.author_id NOT IN (SELECT blocked_id FROM blocks WHERE user_id = :me)
    """

    def _row(self, row: sqlite3.Row) -> dict[str, Any]:
        payload = json.loads(row["payload"])
        avg = row["rating_avg"]
        count = row["rating_count"]
        return {
            "id": row["id"],
            "author_id": row["author_id"],
            "author_name": row["author_name"],
            "name": row["name"],
            "created_at": row["created_at"],
            "recipe": payload["recipe"],
            "items": payload["items"],
            "rating_avg": round(avg, 2) if avg is not None else None,
            "rating_count": count,
            "score": round(bayesian_score(avg, count), 3),
            "my_rating": row["my_rating"],
        }

    def get(self, build_id: str, user_id: str) -> dict[str, Any] | None:
        row = self.db.execute(self._SELECT + " AND b.id = :id GROUP BY b.id",
                              {"me": user_id, "id": build_id}).fetchone()
        return self._row(row) if row else None

    def list(self, user_id: str, recipe_id: str | None = None, sort: str = "top",
             limit: int = 50, mine: bool = False) -> list[dict[str, Any]]:
        sql = self._SELECT
        params: dict[str, Any] = {"me": user_id, "limit": limit}
        if recipe_id:
            sql += " AND b.recipe_id = :recipe"
            params["recipe"] = recipe_id
        if mine:
            sql += " AND b.author_id = :me"
        sql += " GROUP BY b.id"
        rows = [self._row(r) for r in self.db.execute(sql, params).fetchall()]
        if sort == "new":
            rows.sort(key=lambda b: b["created_at"], reverse=True)
        else:
            rows.sort(key=lambda b: (b["score"], b["rating_count"], b["created_at"]), reverse=True)
        return rows[:limit]

    # --- рецепты пользователей ---

    def recipes(self, user_id: str, sort: str = "top", limit: int = 50) -> list[dict[str, Any]]:
        """Свои рецепты пользователей, опубликованные вместе со сборками.

        Автор рецепта — тот, кто опубликовал первую сборку; текст рецепта берём из его
        последней публикации. Рейтинг — по всем сборкам рецепта."""
        builds = [b for b in self.list(user_id, sort="new", limit=10_000) if b["recipe"]["id"].startswith("user-")]
        # время с точностью до секунды: при совпадении порядок публикации — по номеру строки
        seq = {row[0]: row[1] for row in self.db.execute("SELECT id, rowid FROM builds")}
        grouped: dict[str, list[dict[str, Any]]] = {}
        for b in builds:
            grouped.setdefault(b["recipe"]["id"], []).append(b)
        result = []
        for recipe_id, items in grouped.items():
            items.sort(key=lambda b: (b["created_at"], seq.get(b["id"], 0)))
            first = items[0]
            own = [b for b in items if b["author_id"] == first["author_id"]]
            latest = own[-1]
            count = sum(b["rating_count"] for b in items)
            total = sum((b["rating_avg"] or 0) * b["rating_count"] for b in items)
            avg = round(total / count, 2) if count else None
            best = max(items, key=lambda b: (b["score"], b["rating_count"]))
            result.append({
                "recipe": latest["recipe"],
                "author_id": first["author_id"],
                "author_name": first["author_name"],
                "created_at": first["created_at"],
                "updated_at": latest["created_at"],
                "builds_count": len(items),
                "rating_avg": avg,
                "rating_count": count,
                "score": round(bayesian_score(avg, count), 3),
                "best_build_id": best["id"],
            })
        if sort == "new":
            result.sort(key=lambda r: r["created_at"], reverse=True)
        else:
            result.sort(key=lambda r: (r["score"], r["builds_count"], r["created_at"]), reverse=True)
        return result[:limit]

    def choices(self, recipe_id: str, user_id: str, top: int = 3) -> dict[str, Any]:
        """Какие продукты чаще всего выбирают для каждого ингредиента рецепта."""
        builds = self.list(user_id, recipe_id=recipe_id, limit=10_000)
        counts: dict[str, dict[str, int]] = {}
        products: dict[str, dict[str, Any]] = {}
        for b in builds:
            for item in b["items"]:
                pid = item["product"]["id"]
                products[pid] = item["product"]
                per = counts.setdefault(item["ingredient_id"], {})
                per[pid] = per.get(pid, 0) + 1
        ingredients = {}
        for ingredient_id, per in counts.items():
            ranked = sorted(per.items(), key=lambda kv: (-kv[1], products[kv[0]]["name"]))[:top]
            ingredients[ingredient_id] = [{"product": products[pid], "count": n} for pid, n in ranked]
        return {"recipe_id": recipe_id, "builds": len(builds), "ingredients": ingredients}

    # --- оценки ---

    def rate(self, build_id: str, user_id: str, author_name: str, data: RatingIn) -> None:
        self.db.execute(
            "INSERT INTO ratings (build_id, user_id, author_name, stars, comment, created_at)"
            " VALUES (?, ?, ?, ?, ?, ?)"
            " ON CONFLICT(build_id, user_id) DO UPDATE SET"
            " stars = excluded.stars, comment = excluded.comment,"
            " author_name = excluded.author_name, created_at = excluded.created_at",
            (build_id, user_id, author_name, data.stars, data.comment, _now()),
        )
        self.db.commit()

    def ratings(self, build_id: str, user_id: str) -> list[dict[str, Any]]:
        rows = self.db.execute(
            "SELECT * FROM ratings WHERE build_id = ?"
            " AND user_id NOT IN (SELECT blocked_id FROM blocks WHERE user_id = ?)"
            " ORDER BY created_at DESC",
            (build_id, user_id),
        ).fetchall()
        return [{"user_id": r["user_id"], "author_name": r["author_name"], "stars": r["stars"],
                 "comment": r["comment"], "created_at": r["created_at"]} for r in rows]

    # --- модерация ---

    def report(self, build_id: str, user_id: str, reason: str) -> None:
        self.db.execute(
            "INSERT OR IGNORE INTO reports (build_id, user_id, reason, created_at) VALUES (?, ?, ?, ?)",
            (build_id, user_id, reason, _now()),
        )
        count = self.db.execute("SELECT COUNT(*) FROM reports WHERE build_id = ?", (build_id,)).fetchone()[0]
        if count >= HIDE_AFTER_REPORTS:
            self.db.execute("UPDATE builds SET hidden = 1 WHERE id = ?", (build_id,))
        self.db.commit()

    def block(self, user_id: str, blocked_id: str) -> None:
        self.db.execute("INSERT OR IGNORE INTO blocks (user_id, blocked_id) VALUES (?, ?)", (user_id, blocked_id))
        self.db.commit()

    def author_of(self, build_id: str) -> str | None:
        row = self.db.execute("SELECT author_id FROM builds WHERE id = ?", (build_id,)).fetchone()
        return row["author_id"] if row else None
