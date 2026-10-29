"""Тестовые данные для эмулятора (tools/seed_demo.py) создаются и видны через API."""

import importlib.util
from pathlib import Path

from tests.helpers import make_client


def test_seed_demo(tmp_path):
    spec = importlib.util.spec_from_file_location("seed_demo", Path(__file__).resolve().parents[2] / "tools" / "seed_demo.py")
    seed = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(seed)
    seed.main(str(tmp_path / "test.db"))

    client = make_client(tmp_path)  # та же база: tmp_path / "test.db"
    login = client.post("/auth/login", json={"email": "demo@vyborvkusa.test", "password": "demo12345"})
    assert login.status_code == 200, login.text
    headers = {"Authorization": f"Bearer {login.json()['token']}"}
    assert login.json()["user"]["email_verified"] is True
    builds = client.get("/community/builds").json()
    assert {b["name"] for b in builds} >= {"Карбонара по-римски", "Бабушкин пирог", "Моя карбонара"}
    notes = client.get("/notifications", headers=headers).json()
    assert notes["unread_count"] == 1 and "сыра" in notes["items"][0]["body"]
    assert any(r["recipe"]["id"] == "user-demo-pie" for r in client.get("/community/recipes").json())
