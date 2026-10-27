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
    tools = rpc("tools/list", {}, rid=2)
    for t in tools.get("result", {}).get("tools", []):
        note(f"tool {t['name']}", json.dumps({"description": t.get("description"), "schema": t.get("inputSchema")},
                                             ensure_ascii=False))
    names = [t["name"] for t in tools.get("result", {}).get("tools", [])]
    search = next((n for n in names if "search" in n), None)
    if search:
        schema = next(t for t in tools["result"]["tools"] if t["name"] == search)["inputSchema"]
        key = next(iter(schema.get("properties", {"q": 0})))
        res = rpc("tools/call", {"name": search, "arguments": {key: "сыр пармезан"}}, rid=3)
        note("search result", json.dumps(res.get("result", res), ensure_ascii=False))
    cart = next((n for n in names if "cart" in n), None)
    if cart:
        note("cart schema", json.dumps(next(t for t in tools["result"]["tools"] if t["name"] == cart)["inputSchema"],
                                       ensure_ascii=False))
except Exception as e:  # noqa: BLE001
    note("error", repr(e))
    sys.exit(0)
