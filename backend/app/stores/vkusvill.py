"""ВкусВилл через их официальный экспериментальный MCP-сервер (https://mcp.vkusvill.ru/mcp).

Без браузера: обычные HTTP-запросы JSON-RPC. Поиск отдаёт цену и фасовку, а инструмент
vkusvill_cart_link_create собирает ссылку на корзину — по ней корзина открывается
в приложении или на сайте ВкусВилл. Это единственный известный нам магазин,
куда корзину можно передать целиком.
Источник: блог ВкусВилл на Хабре, https://habr.com/ru/post/981866
"""

from __future__ import annotations

import asyncio
import html
import json
import logging
from decimal import Decimal
from typing import Any

from ..models import City, Offer, StoreInfo
from ..units import parse_size
from .base import StoreUnavailable

log = logging.getLogger(__name__)

STORE_ID = "vkusvill"
MCP_URL = "https://mcp.vkusvill.ru/mcp"
# Доставка ВкусВилл точно работает в Москве и Петербурге; другие города — после проверки.
CITIES = {"msk", "spb"}
MAX_CART_ITEMS = 100

INFO = StoreInfo(
    id=STORE_ID,
    name="ВкусВилл",
    app_store_url="https://apps.apple.com/app/id1399903464",
    web_url="https://vkusvill.ru",
)


class MCPError(Exception):
    pass


def _clean(name: str) -> str:
    return " ".join(html.unescape(name).replace("\xa0", " ").split())


def parse_search(payload: dict[str, Any]) -> list[Offer]:
    """Ответ vkusvill_products_search (поле text, разобранное из JSON) → предложения."""
    data = payload.get("data") or {}
    offers: list[Offer] = []
    for item in data.get("items") or []:
        price = (item.get("price") or {}).get("current")
        if price is None or item.get("id") is None:
            continue
        title = _clean(item.get("name") or "")
        unit_name = (item.get("unit") or "").lower()
        weight = item.get("weight") or {}
        old = (item.get("price") or {}).get("old")

        if unit_name == "кг":
            amount, unit, weighted = 1000.0, "g", True
        else:
            weighted = False
            size = parse_size(title)
            if size:
                amount, unit = size
            elif weight.get("value") and (weight.get("unit") or "").lower() == "кг":
                amount, unit = round(float(weight["value"]) * 1000, 1), "g"
            elif weight.get("value") and (weight.get("unit") or "").lower() == "л":
                amount, unit = round(float(weight["value"]) * 1000, 1), "ml"
            else:
                amount, unit = 1.0, "pcs"

        offers.append(Offer(
            store_id=STORE_ID,
            sku=str(item["id"]),
            title=title,
            price=Decimal(str(price)).quantize(Decimal("0.01")),
            package_amount=amount,
            unit=unit,
            is_weighted=weighted,
            regular_price=Decimal(str(old)).quantize(Decimal("0.01")) if old else None,
        ))
    return offers


def cart_quantity(quantity: float) -> float:
    """ВкусВилл принимает количество 0.01..40 (штуки или кг для весовых)."""
    return max(0.01, min(40.0, round(quantity, 2)))


class VkusVillAdapter:
    info = INFO

    def __init__(self, url: str = MCP_URL, client: Any = None):
        self._url = url
        self._client = client
        self._session: str | None = None
        self._next_id = 0
        self._lock = asyncio.Lock()

    async def _http(self) -> Any:
        if self._client is None:
            import httpx
            self._client = httpx.AsyncClient(timeout=30, headers={"User-Agent": "VyborVkusa/1.0"})
        return self._client

    async def _post(self, body: dict[str, Any]) -> dict[str, Any] | None:
        client = await self._http()
        headers = {"Content-Type": "application/json", "Accept": "application/json, text/event-stream"}
        if self._session:
            headers["Mcp-Session-Id"] = self._session
        resp = await client.post(self._url, content=json.dumps(body), headers=headers)
        if resp.status_code >= 400:
            raise MCPError(f"HTTP {resp.status_code}")
        self._session = resp.headers.get("mcp-session-id") or self._session
        if "id" not in body:
            return None
        text = resp.text
        if "event-stream" in resp.headers.get("content-type", ""):
            for line in text.splitlines():
                if line.startswith("data:"):
                    msg = json.loads(line[5:].strip())
                    if msg.get("id") == body["id"]:
                        return msg
            raise MCPError("пустой ответ")
        return json.loads(text)

    async def _rpc(self, method: str, params: dict[str, Any]) -> dict[str, Any]:
        self._next_id += 1
        msg = await self._post({"jsonrpc": "2.0", "id": self._next_id, "method": method, "params": params})
        assert msg is not None
        if "error" in msg:
            raise MCPError(str(msg["error"]))
        return msg["result"]

    async def _ensure_session(self) -> None:
        if self._session is not None:
            return
        await self._rpc("initialize", {"protocolVersion": "2025-03-26", "capabilities": {},
                                       "clientInfo": {"name": "vyborvkusa", "version": "1.0"}})
        await self._post({"jsonrpc": "2.0", "method": "notifications/initialized"})

    async def call(self, tool: str, arguments: dict[str, Any]) -> dict[str, Any]:
        """Вызов инструмента; при потере сессии — одна повторная попытка с новой."""
        async with self._lock:
            for attempt in (1, 2):
                try:
                    await self._ensure_session()
                    result = await self._rpc("tools/call", {"name": tool, "arguments": arguments})
                    break
                except MCPError as e:
                    self._session = None
                    if attempt == 2:
                        raise StoreUnavailable(f"ВкусВилл: {e}") from e
                except Exception as e:  # сеть, таймаут
                    self._session = None
                    raise StoreUnavailable(f"ВкусВилл: {e}") from e
        if result.get("isError"):
            raise StoreUnavailable("ВкусВилл вернул ошибку")
        content = result.get("content") or [{}]
        try:
            return json.loads(content[0].get("text") or "{}")
        except json.JSONDecodeError as e:
            raise StoreUnavailable("ВкусВилл: неожиданный ответ") from e

    async def delivers_to(self, city: City) -> bool:
        return city.id in CITIES

    async def search(self, city: City, query: str) -> list[Offer]:
        payload = await self.call("vkusvill_products_search", {
            "q": query[:255], "vvonly": 0, "limit": 10, "mode": "custom",
            "fields": ["id", "name", "price", "unit", "weight", "url"],
        })
        return parse_search(payload)

    async def cart_link(self, items: list[tuple[str, float]]) -> str:
        """items: (sku, количество) → ссылка на корзину ВкусВилл."""
        products = [{"id": int(sku), "q": cart_quantity(q)} for sku, q in items if sku.isdigit()][:MAX_CART_ITEMS]
        if not products:
            raise ValueError("Нет товаров ВкусВилл для корзины")
        payload = await self.call("vkusvill_cart_link_create", {"products": products})
        link = (payload.get("data") or {}).get("link")
        if not payload.get("ok") or not link:
            raise StoreUnavailable("ВкусВилл не создал ссылку на корзину")
        return link

    async def close(self) -> None:
        if self._client is not None:
            await self._client.aclose()
            self._client = None
