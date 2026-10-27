import io
from datetime import datetime, timedelta, timezone

import pytest
from PIL import Image

from tests.helpers import make_client, register


def jpeg(w=1200, h=800, gps=True):
    img = Image.new("RGB", (w, h), (180, 90, 40))
    exif = Image.Exif()
    if gps:
        exif[0x8825] = {2: (55.0, 45.0, 0.0)}  # координаты съёмки
    buf = io.BytesIO()
    img.save(buf, "JPEG", exif=exif)
    return buf.getvalue()


@pytest.fixture
def client(tmp_path):
    with make_client(tmp_path) as c:
        c.media = tmp_path / "media"
        yield c


def upload(client, headers, recipe="borscht", data=None):
    return client.post(f"/recipes/{recipe}/photos", content=data or jpeg(),
                       headers={**headers, "Content-Type": "image/jpeg"})


def test_like_unlike_and_my_likes(client):
    alice, _ = register(client)
    assert client.put("/recipes/borscht/like").status_code == 401
    assert client.put("/recipes/borscht/like", headers=alice).status_code == 204
    assert client.put("/recipes/borscht/like", headers=alice).status_code == 204  # повтор не удваивает
    client.put("/recipes/plov/like", headers=alice)
    assert set(client.get("/me/likes", headers=alice).json()) == {"borscht", "plov"}

    summary = client.get("/recipes/borscht", headers=alice).json()
    assert summary["likes"] == 1 and summary["liked_by_me"] is True
    assert client.get("/recipes/borscht").json()["liked_by_me"] is False  # без входа

    client.delete("/recipes/borscht/like", headers=alice)
    assert client.get("/me/likes", headers=alice).json() == ["plov"]


def test_invalid_recipe_id(client):
    alice, _ = register(client)
    assert client.put("/recipes/..%2Fetc/like", headers=alice).status_code in (404, 422)
    assert client.put("/recipes/BAD_ID/like", headers=alice).status_code == 422


def test_popular_orders_by_recent_likes(client):
    users = [register(client)[0] for _ in range(3)]
    for h in users:
        client.put("/recipes/plov/like", headers=h)
    for h in users[:2]:
        client.put("/recipes/borscht/like", headers=h)
    client.put("/recipes/omelet/like", headers=users[0])

    # старые лайки (больше 30 дней) не делают рецепт популярным сейчас
    old = (datetime.now(timezone.utc) - timedelta(days=60)).isoformat(timespec="seconds")
    db = client.app.state.stores.recipes.db
    for i in range(5):
        db.execute("INSERT INTO recipe_likes VALUES ('charlotte', ?, ?)", (f"old-user-{i}", old))
    db.commit()

    popular = client.get("/recipes/popular").json()
    assert [p["recipe_id"] for p in popular][:3] == ["plov", "borscht", "omelet"]
    charlotte = next(p for p in popular if p["recipe_id"] == "charlotte")
    assert charlotte["likes"] == 5 and charlotte["recent_likes"] == 0


def test_photo_upload_strips_metadata_and_resizes(client):
    alice, _ = register(client, name="Алиса")
    r = upload(client, alice, data=jpeg(3000, 2000))
    assert r.status_code == 201, r.text
    photo = r.json()
    assert photo["author_name"] == "Алиса"
    assert max(photo["width"], photo["height"]) == 1600

    stored = client.get(photo["url"])
    assert stored.status_code == 200 and stored.headers["content-type"] == "image/jpeg"
    img = Image.open(io.BytesIO(stored.content))
    assert dict(img.getexif()) == {}  # геолокация и прочие метаданные удалены
    assert client.get(photo["thumb_url"]).status_code == 200

    summary = client.get("/recipes/borscht").json()
    assert [p["id"] for p in summary["photos"]] == [photo["id"]]
    covers = client.post("/recipes/covers", json={"ids": ["borscht", "plov"]}).json()
    assert set(covers) == {"borscht"}


def test_photo_requires_verified_email_and_valid_image(client):
    unverified, _ = register(client, verify=False)
    assert upload(client, unverified).status_code == 403
    alice, _ = register(client)
    assert upload(client, alice, data=b"definitely not an image").status_code == 422
    tiny = io.BytesIO()
    Image.new("RGB", (100, 100)).save(tiny, "PNG")
    assert upload(client, alice, data=tiny.getvalue()).status_code == 422


def test_photo_upload_daily_limit(client):
    alice, _ = register(client)
    small = jpeg(300, 300, gps=False)
    for _ in range(20):
        assert upload(client, alice, data=small).status_code == 201
    assert upload(client, alice, data=small).status_code == 429


def test_delete_own_photo_only(client):
    alice, _ = register(client)
    bob, _ = register(client)
    photo = upload(client, alice).json()
    assert client.delete(f"/photos/{photo['id']}", headers=bob).status_code == 404
    assert client.delete(f"/photos/{photo['id']}", headers=alice).status_code == 204
    assert not (client.media / "photos" / f"{photo['id']}.jpg").exists()
    assert client.get("/recipes/borscht").json()["photos"] == []


def test_reports_hide_photo_and_blocks_filter(client):
    alice, alice_user = register(client)
    photo = upload(client, alice).json()

    bob, _ = register(client)
    client.post("/community/blocks", json={"user_id": alice_user["id"]}, headers=bob)
    assert client.get("/recipes/borscht", headers=bob).json()["photos"] == []

    carol, _ = register(client)
    assert client.post(f"/photos/{photo['id']}/report", json={"reason": "не еда"}, headers=carol).status_code == 204
    # пожаловавшийся перестаёт видеть фото сразу, остальные — пока жалоб мало — видят
    assert client.get("/recipes/borscht", headers=carol).json()["photos"] == []
    assert len(client.get("/recipes/borscht").json()["photos"]) == 1

    for _ in range(2):
        h, _ = register(client)
        assert client.post(f"/photos/{photo['id']}/report", json={"reason": "не еда"}, headers=h).status_code == 204
    # третья жалоба — фото удалено вместе с файлами
    assert client.get("/recipes/borscht").json()["photos"] == []
    assert not (client.media / "photos" / f"{photo['id']}.jpg").exists()
    assert client.post(f"/photos/{photo['id']}/report", json={"reason": "x"}, headers=carol).status_code == 404


def test_account_deletion_removes_photos_and_likes(client):
    alice, _ = register(client)
    photo = upload(client, alice).json()
    client.put("/recipes/borscht/like", headers=alice)
    client.delete("/auth/me", headers=alice)
    assert not (client.media / "photos" / f"{photo['id']}.jpg").exists()
    assert client.get("/recipes/borscht").json()["likes"] == 0
