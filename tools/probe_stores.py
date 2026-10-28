"""Проверка открытых API магазинов из CI: Лента, Магнит, Ашан, Купер (Санкт-Петербург).
Запуск: python3 tools/probe_stores.py lenta|magnit|auchan|kuper
Результаты печатаются аннотациями GitHub (::notice), чтобы их было видно без логов."""
import json
import sys
import uuid

import httpx

SPB = (59.9343, 30.3351)  # Невский проспект


def note(title, text):
    text = str(text).replace("%", "%25").replace("\r", "").replace("\n", "%0A")
    print(f"::notice title={title}::{text[:3800]}")


def short(obj, n=1500):
    return json.dumps(obj, ensure_ascii=False)[:n]


def lenta():
    api = httpx.Client(base_url="https://integration.api.lenta.com", timeout=30,
                       headers={"Accept": "application/json", "User-Agent": "VyborVkusa/0.1"})
    r = api.get("/v1/stores", params={"retailBrand": "lo"})
    note("lenta stores", f"{r.status_code} {r.text[:300]}")
    stores = r.json()["stores"]
    spb = [s for s in stores if "Петербург" in (s.get("cityName") or "")]
    note("lenta spb", f"всего {len(stores)}, в СПб {len(spb)}; типы {sorted({s.get('type') for s in spb})}; "
         f"пример {short(spb[0], 800) if spb else '-'}")
    store = next(s for s in spb if s.get("type") != "zoo")
    for channel in ("lo", "locc"):
        r = api.get("/catalog/v1/items", params={"retailBrand": "lo", "stores": store["id"], "channel": channel,
                                                  "query": "молоко", "limit": 3})
        note(f"lenta search {channel}", f"{r.status_code} {short(r.json() if r.status_code == 200 else r.text, 2500)}")
    r = api.get("/catalog/v1/items", params={"retailBrand": "lo", "stores": store["id"], "channel": "lo",
                                              "query": "картофель", "limit": 2})
    note("lenta weighted", short(r.json(), 2500))
    item = r.json()["items"][0]["id"]
    r = api.get(f"/catalog/v1/items/{item}", params={"retailBrand": "lo", "stores": store["id"], "channel": "lo"})
    note("lenta item", f"{r.status_code} {short(r.json(), 3000)}")
    for path in ("/v1/cart", "/cart/v1/deeplink", "/v1/deeplinks"):
        r = api.get(path, params={"retailBrand": "lo"})
        note(f"lenta {path}", f"{r.status_code} {r.text[:200]}")


def magnit():
    headers = {"user-agent": "Dalvik/2.1.0 (Linux; U; Android 14; SM-S918B Build/UP1A.231005.007)",
               "x-app-version": "8.124.0", "x-device-id": str(uuid.uuid4()), "x-device-platform": "Android",
               "x-platform-version": "36", "content-type": "application/json"}
    api = httpx.Client(base_url="https://middle-api.magnit.ru/", timeout=30, headers=headers)
    r = api.post("v1/stores-facade/search", json={"filters": {
        "geo": {"typeName": "circle", "coordinates": {"latitude": SPB[0], "longitude": SPB[1]},
                "distance_meters": 3000},
        "deliveryTypeList": ["DELIVERY_TYPE_DELIVERY"]}})
    note("magnit stores", f"{r.status_code} {r.text[:1200]}")
    stores = [s for s in r.json()["items"]["items"] if s["externalId"]["owner"] == "OWNER_MAGNIT"]
    code = stores[0]["externalId"]["storeCode"]
    for q in ("молоко", "картофель"):
        r = api.post("v2/goods/search", json={"storeType": "express", "catalogType": "2", "storeCode": code,
                                              "term": q, "pagination": {"limit": 3, "offset": 0},
                                              "sort": {"order": "desc", "type": "relevance"}})
        note(f"magnit search {q}", f"store {code}: {r.status_code} {r.text[:2500]}")
    good = r.json()["items"][0]["id"]
    r = api.get(f"v2/goods/{good}/stores/{code}", params={"storetype": "express", "catalogtype": "2"})
    note("magnit good", f"{r.status_code} {r.text[:3000]}")
    # Каталог магазина у дома (не экспресс-доставка)
    r = api.post("v2/goods/search", json={"storeType": "MM", "catalogType": "1", "storeCode": code,
                                          "term": "молоко", "pagination": {"limit": 2, "offset": 0},
                                          "sort": {"order": "desc", "type": "relevance"}})
    note("magnit search MM", f"{r.status_code} {r.text[:800]}")


def auchan():
    web = httpx.Client(timeout=30, follow_redirects=True, headers={
        "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148",
        "Accept": "application/json"})
    urls = ["https://www.auchan.ru/v1/shops?merchantId=1",
            "https://www.auchan.ru/v1/search?query=%D0%BC%D0%BE%D0%BB%D0%BE%D0%BA%D0%BE&merchantId=1&page=1&perPage=3",
            "https://www.auchan.ru/v1/catalog/products?merchantId=1&page=1&perPage=3&filter%5Bquery%5D=%D0%BC%D0%BE%D0%BB%D0%BE%D0%BA%D0%BE",
            "https://www.auchan.ru/v1/catalog/products?merchantId=1&page=1&perPage=3&filter%5Bcategory%5D=moloko",
            "https://www.auchan.ru/search/?q=%D0%BC%D0%BE%D0%BB%D0%BE%D0%BA%D0%BE"]
    for u in urls:
        try:
            r = web.get(u)
            note("auchan", f"{u[24:90]} → {r.status_code} {r.headers.get('content-type')} {r.text[:900]}")
        except Exception as e:  # noqa: BLE001
            note("auchan", f"{u[24:90]} → {e!r}")


def kuper():
    from curl_cffi import requests
    base = "https://web.kuper.ru"
    s = requests.Session(impersonate="chrome")
    r = s.get(f"{base}/?city_name=sankt-peterburg", timeout=30)
    note("kuper warm", f"{r.status_code} cookies={sorted(s.cookies.keys())}")
    headers = {"content-type": "application/json", "accept": "application/json", "referer": f"{base}/",
               "origin": base, "x-requested-with": "XMLHttpRequest"}
    r = s.get(f"{base}/api/v3/mweb/shelves?lat={SPB[0]}&lon={SPB[1]}&shelves_codes_to_exclude=alcohol",
              headers={k: v for k, v in headers.items() if k != "content-type"}, timeout=30)
    note("kuper shelves", f"{r.status_code} {r.text[:300]}")
    shop = ((r.json().get("data") or {}).get("shelves_data") or {}).get("shop") or {}
    stores = list(shop.values()) if isinstance(shop, dict) else list(shop)
    note("kuper retailers", ", ".join(f"{(x.get('retailer') or {}).get('name')}={x.get('id')}" for x in stores)[:3000]
         or short(shop, 2000))
    for want in ("Лента", "АШАН", "Магнит"):
        st = next((x for x in stores if want.lower() in ((x.get("retailer") or {}).get("name") or "").lower()), None)
        if not st:
            continue
        r = s.post(f"{base}/api/web/v1/products", data=json.dumps({"q": "молоко", "store_id": str(st["id"])}),
                   headers=headers, timeout=30)
        body = r.json() if r.status_code == 200 else r.text
        items = body.get("products", [])[:2] if isinstance(body, dict) else body
        note(f"kuper {want}", f"{r.status_code} {short(items, 2500)}")


if __name__ == "__main__":
    {"lenta": lenta, "magnit": magnit, "auchan": auchan, "kuper": kuper}[sys.argv[1]]()
