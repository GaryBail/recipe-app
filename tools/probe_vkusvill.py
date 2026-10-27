"""Проверка MCP-сервера ВкусВилл: список инструментов, поиск и ссылка на корзину.
Печатает результаты как аннотации GitHub (::notice), чтобы их было видно без логов."""
import json
import sys
import urllib.request

URL = "https://mcp.vkusvill.ru/mcp"
session = None


def note(title, text):
    text = str(text).replace("%", "%25").replace("\r", "").replace("\n", "%0A")
    print(f"::notice title={title}::{text[:3800]}")


def rpc(method, params=None, rid=1, notify=False):
    global session
    body = {"jsonrpc": "2.0", "method": method}
    if not notify:
        body["id"] = rid
    if params is not None:
        body["params"] = params
    req = urllib.request.Request(URL, data=json.dumps(body).encode(), method="POST", headers={
        "Content-Type": "application/json", "Accept": "application/json, text/event-stream",
        "User-Agent": "VyborVkusa/0.1", **({"Mcp-Session-Id": session} if session else {})})
    with urllib.request.urlopen(req, timeout=30) as resp:
        session = resp.headers.get("Mcp-Session-Id") or session
        raw = resp.read().decode("utf-8", "replace")
        ctype = resp.headers.get("Content-Type", "")
    if notify:
        return None
    if "event-stream" in ctype:
        datas = [l[5:].strip() for l in raw.splitlines() if l.startswith("data:")]
        for d in datas:
            msg = json.loads(d)
            if msg.get("id") == rid:
                return msg
        raise RuntimeError(raw[:500])
    return json.loads(raw)


try:
    init = rpc("initialize", {"protocolVersion": "2025-03-26", "capabilities": {},
                              "clientInfo": {"name": "vyborvkusa", "version": "0.1"}})
    note("init", json.dumps(init.get("result", init), ensure_ascii=False)[:1500])
    rpc("notifications/initialized", notify=True)
    res = rpc("tools/call", {"name": "vkusvill_products_search",
                             "arguments": {"q": "пармезан", "vvonly": 0, "limit": 3, "mode": "custom",
                                           "fields": ["id", "name", "price", "unit", "weight", "url"]}}, rid=3)
    note("search", json.dumps(res.get("result", res), ensure_ascii=False))
    text = res["result"]["content"][0]["text"]
    data = json.loads(text)
    items = data.get("data", {}).get("items") or data.get("items") or []
    first = items[0]["id"] if items else None
    note("first id", first)
    if first:
        link = rpc("tools/call", {"name": "vkusvill_cart_link_create",
                                  "arguments": {"products": [{"id": int(first), "q": 1}]}}, rid=4)
        note("cart link", json.dumps(link.get("result", link), ensure_ascii=False))
except Exception as e:  # noqa: BLE001
    note("error", repr(e))
    sys.exit(0)
