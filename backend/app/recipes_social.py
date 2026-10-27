"""Рецепты: лайки (избранное), популярное и фотографии от пользователей.

Фото проверяются и пережимаются: остаётся только картинка — метаданные (в том числе
геолокация из EXIF) удаляются. Хранятся на диске в MEDIA_DIR и раздаются по /media/...
"""

from __future__ import annotations

import io
import re
import sqlite3
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

from pydantic import BaseModel, Field

RECIPE_ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,99}$")
MAX_UPLOAD_BYTES = 10 * 1024 * 1024
MAX_SIDE = 1600
THUMB_SIDE = 600
MAX_PIXELS = 50_000_000          # защита от «бомб» с огромным разрешением
HIDE_AFTER_REPORTS = 3
POPULAR_DAYS = 30
UPLOADS_PER_DAY = (20, 24 * 3600)


class PhotoReportIn(BaseModel):
    reason: str = Field(min_length=1, max_length=300)


class BadImage(Exception):
    pass


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _iso(dt: datetime) -> str:
    return dt.isoformat(timespec="seconds")


def process_image(data: bytes) -> tuple[bytes, bytes, int, int]:
    """Проверяет картинку и возвращает (jpeg, миниатюра, ширина, высота) без метаданных."""
    from PIL import Image, ImageOps, UnidentifiedImageError

    Image.MAX_IMAGE_PIXELS = MAX_PIXELS
    if len(data) > MAX_UPLOAD_BYTES:
        raise BadImage("Фото больше 10 МБ")
    try:
        with Image.open(io.BytesIO(data)) as probe:
            if probe.format not in ("JPEG", "PNG", "WEBP"):
                raise BadImage("Поддерживаются JPEG, PNG и WebP")
            probe.verify()
        img = Image.open(io.BytesIO(data))
        img.load()
    except BadImage:
        raise
    except (UnidentifiedImageError, OSError, Image.DecompressionBombError, SyntaxError) as e:
        raise BadImage("Файл не похож на изображение") from e

    img = ImageOps.exif_transpose(img)  # повернуть по EXIF, прежде чем его выбросить
    if img.mode != "RGB":
        background = Image.new("RGB", img.size, (255, 255, 255))
        rgba = img.convert("RGBA")
        background.paste(rgba, mask=rgba.split()[-1])
        img = background
    if min(img.size) < 200:
        raise BadImage("Слишком маленькое фото (меньше 200 пикселей)")

    full = img.copy()
    full.thumbnail((MAX_SIDE, MAX_SIDE))
    thumb = img.copy()
    thumb.thumbnail((THUMB_SIDE, THUMB_SIDE))

    def encode(im) -> bytes:
        out = io.BytesIO()
        im.save(out, "JPEG", quality=85, optimize=True, progressive=True)  # без exif=…
        return out.getvalue()

    return encode(full), encode(thumb), full.width, full.height


class RecipeSocialStore:
    def __init__(self, db: sqlite3.Connection, media_dir: str):
        self.db = db
        self.media = Path(media_dir)
        (self.media / "photos").mkdir(parents=True, exist_ok=True)
        self.db.executescript("""
            CREATE TABLE IF NOT EXISTS recipe_likes (
                recipe_id TEXT NOT NULL,
                user_id TEXT NOT NULL,
                created_at TEXT NOT NULL,
                PRIMARY KEY (recipe_id, user_id)
            );
            CREATE INDEX IF NOT EXISTS recipe_likes_time ON recipe_likes(created_at);
            CREATE TABLE IF NOT EXISTS recipe_photos (
                id TEXT PRIMARY KEY,
                recipe_id TEXT NOT NULL,
                user_id TEXT NOT NULL,
                author_name TEXT NOT NULL,
                width INTEGER NOT NULL,
                height INTEGER NOT NULL,
                created_at TEXT NOT NULL,
                hidden INTEGER NOT NULL DEFAULT 0
            );
            CREATE INDEX IF NOT EXISTS recipe_photos_recipe ON recipe_photos(recipe_id);
            CREATE TABLE IF NOT EXISTS photo_reports (
                photo_id TEXT NOT NULL REFERENCES recipe_photos(id) ON DELETE CASCADE,
                user_id TEXT NOT NULL,
                reason TEXT NOT NULL,
                created_at TEXT NOT NULL,
                PRIMARY KEY (photo_id, user_id)
            );
        """)
        self.db.commit()

    # --- лайки ---

    def like(self, recipe_id: str, user_id: str) -> None:
        self.db.execute("INSERT OR IGNORE INTO recipe_likes (recipe_id, user_id, created_at) VALUES (?, ?, ?)",
                        (recipe_id, user_id, _iso(_now())))
        self.db.commit()

    def unlike(self, recipe_id: str, user_id: str) -> None:
        self.db.execute("DELETE FROM recipe_likes WHERE recipe_id = ? AND user_id = ?", (recipe_id, user_id))
        self.db.commit()

    def liked_ids(self, user_id: str) -> list[str]:
        rows = self.db.execute("SELECT recipe_id FROM recipe_likes WHERE user_id = ? ORDER BY created_at DESC",
                               (user_id,)).fetchall()
        return [r["recipe_id"] for r in rows]

    def likes_count(self, recipe_id: str) -> int:
        return self.db.execute("SELECT COUNT(*) FROM recipe_likes WHERE recipe_id = ?", (recipe_id,)).fetchone()[0]

    # --- фото ---

    def _photo_json(self, row: sqlite3.Row) -> dict[str, Any]:
        return {
            "id": row["id"], "recipe_id": row["recipe_id"], "author_id": row["user_id"],
            "author_name": row["author_name"], "width": row["width"], "height": row["height"],
            "url": f"/media/photos/{row['id']}.jpg", "thumb_url": f"/media/photos/{row['id']}_thumb.jpg",
            "created_at": row["created_at"],
        }

    def add_photo(self, recipe_id: str, user_id: str, author_name: str, data: bytes) -> dict[str, Any]:
        full, thumb, w, h = process_image(data)
        photo_id = uuid.uuid4().hex
        (self.media / "photos" / f"{photo_id}.jpg").write_bytes(full)
        (self.media / "photos" / f"{photo_id}_thumb.jpg").write_bytes(thumb)
        self.db.execute(
            "INSERT INTO recipe_photos (id, recipe_id, user_id, author_name, width, height, created_at)"
            " VALUES (?, ?, ?, ?, ?, ?, ?)",
            (photo_id, recipe_id, user_id, author_name, w, h, _iso(_now())),
        )
        self.db.commit()
        return self._photo_json(self.db.execute("SELECT * FROM recipe_photos WHERE id = ?", (photo_id,)).fetchone())

    def photos(self, recipe_id: str, me: str) -> list[dict[str, Any]]:
        rows = self.db.execute(
            "SELECT * FROM recipe_photos WHERE recipe_id = ? AND hidden = 0"
            " AND user_id NOT IN (SELECT blocked_id FROM blocks WHERE user_id = ?)"
            " ORDER BY created_at",
            (recipe_id, me),
        ).fetchall()
        return [self._photo_json(r) for r in rows]

    def _remove_files(self, photo_id: str) -> None:
        for name in (f"{photo_id}.jpg", f"{photo_id}_thumb.jpg"):
            (self.media / "photos" / name).unlink(missing_ok=True)

    def delete_photo(self, photo_id: str, user_id: str) -> bool:
        cur = self.db.execute("DELETE FROM recipe_photos WHERE id = ? AND user_id = ?", (photo_id, user_id))
        self.db.commit()
        if cur.rowcount:
            self._remove_files(photo_id)
        return cur.rowcount > 0

    def photo_exists(self, photo_id: str) -> bool:
        return self.db.execute("SELECT 1 FROM recipe_photos WHERE id = ? AND hidden = 0",
                               (photo_id,)).fetchone() is not None

    def report_photo(self, photo_id: str, user_id: str, reason: str) -> None:
        self.db.execute("INSERT OR IGNORE INTO photo_reports (photo_id, user_id, reason, created_at) VALUES (?, ?, ?, ?)",
                        (photo_id, user_id, reason, _iso(_now())))
        count = self.db.execute("SELECT COUNT(*) FROM photo_reports WHERE photo_id = ?", (photo_id,)).fetchone()[0]
        if count >= HIDE_AFTER_REPORTS:
            self.db.execute("UPDATE recipe_photos SET hidden = 1 WHERE id = ?", (photo_id,))
        self.db.commit()

    # --- сводка по рецепту и популярное ---

    def summary(self, recipe_id: str, me: str) -> dict[str, Any]:
        liked = me and self.db.execute("SELECT 1 FROM recipe_likes WHERE recipe_id = ? AND user_id = ?",
                                       (recipe_id, me)).fetchone() is not None
        return {"recipe_id": recipe_id, "likes": self.likes_count(recipe_id), "liked_by_me": bool(liked),
                "photos": self.photos(recipe_id, me)}

    def popular(self, me: str, limit: int = 10) -> list[dict[str, Any]]:
        since = _iso(_now() - timedelta(days=POPULAR_DAYS))
        rows = self.db.execute(
            "SELECT recipe_id, COUNT(*) AS total,"
            " SUM(CASE WHEN created_at >= ? THEN 1 ELSE 0 END) AS recent"
            " FROM recipe_likes GROUP BY recipe_id ORDER BY recent DESC, total DESC LIMIT ?",
            (since, limit),
        ).fetchall()
        result = []
        for r in rows:
            photos = self.photos(r["recipe_id"], me)
            result.append({
                "recipe_id": r["recipe_id"], "likes": r["total"], "recent_likes": r["recent"],
                "cover": photos[-1] if photos else None,  # самое свежее фото
            })
        return result

    def covers(self, recipe_ids: list[str], me: str) -> dict[str, dict[str, Any]]:
        """Обложки (последнее фото) для списка рецептов — для карточек на главной."""
        result = {}
        for rid in recipe_ids[:200]:
            photos = self.photos(rid, me)
            if photos:
                result[rid] = photos[-1]
        return result

    def delete_user(self, user_id: str) -> None:
        for r in self.db.execute("SELECT id FROM recipe_photos WHERE user_id = ?", (user_id,)).fetchall():
            self._remove_files(r["id"])
        self.db.execute("DELETE FROM recipe_photos WHERE user_id = ?", (user_id,))
        self.db.execute("DELETE FROM recipe_likes WHERE user_id = ?", (user_id,))
        self.db.execute("DELETE FROM photo_reports WHERE user_id = ?", (user_id,))
        self.db.commit()
