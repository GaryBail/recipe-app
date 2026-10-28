"""Сохраняет живые ответы API магазинов (Санкт-Петербург) в папку для тестовых образцов.
Запускается в CI: python3 tools/probe_dump.py OUT_DIR"""
import json
import pathlib
import sys
import uuid

import httpx

SPB = (59.9343, 30.3351)
OUT = pathlib.Path(sys.argv[1])
OUT.mkdir(parents=True, exist_ok=True)
QUERIES = {"milk": "молоко", "potato": "картофель", "parmesan": "пармезан", "eggs": "яйца"}


def save(name, data):
    if isinstance(data, httpx.Response):
        try:
            data = {"status": data.status_code, "body": data.json()}
        except Exception:  # noqa: BLE001
            data = {"status": data.status_code, "text": data.text[:3000]}
    (OUT / f"{name}.json").write_text(json.dumps(data, ensure_ascii=False, indent=1))


def guard(fn):
    try:
        fn()
    except Exception as e:  # noqa: BLE001
        save(f"{fn.__name__}_error", {"error": repr(e)})


def lenta():
    api = httpx.Client(base_url="https://integration.api.lenta.com", timeout=30,
                       headers={"Accept": "application/json", "User-Agent": "VyborVkusa/0.1"})
    stores = api.get("/v1/stores", params={"retailBrand": "lo"}).json()["stores"]
    spb = [s for s in stores if s.get("cityName") == "Санкт-Петербург"]
    save("lenta_stores_spb", spb)
    hyper = next(s for s in spb if s.get("type") == "hypermarket")
    for key, q in QUERIES.items():
        save(f"lenta_search_{key}", api.get("/catalog/v1/items", params={
            "retailBrand": "lo", "stores": hyper["id"], "channel": "lo", "query": q, "limit": 10}))
    # Цены в разных форматах магазинов одного города
    for s in [next(x for x in spb if x.get("type") == t) for t in ("supermarket", "AL", "EC") if
              any(x.get("type") == t for x in spb)]:
        save(f"lenta_milk_{s['type']}", api.get("/catalog/v1/items", params={
            "retailBrand": "lo", "stores": s["id"], "channel": "lo", "query": "молоко", "limit": 3}))
    item = api.get("/catalog/v1/items", params={"retailBrand": "lo", "stores": hyper["id"], "channel": "lo",
                                                 "query": "картофель", "limit": 1}).json()["items"][0]["id"]
    save("lenta_item", api.get(f"/catalog/v1/items/{item}", params={
        "retailBrand": "lo", "stores": hyper["id"], "channel": "lo"}))


def magnit():
    headers = {"user-agent": "Dalvik/2.1.0 (Linux; U; Android 14; SM-S918B Build/UP1A.231005.007)",
               "x-app-version": "8.124.0", "x-device-id": str(uuid.uuid4()), "x-device-platform": "Android",
               "x-platform-version": "36"}
    api = httpx.Client(base_url="https://middle-api.magnit.ru/", timeout=30, headers=headers)
    stores = api.post("v1/stores-facade/search", json={"filters": {
        "geo": {"typeName": "circle", "coordinates": {"latitude": SPB[0], "longitude": SPB[1]},
                "distance_meters": 3000},
        "deliveryTypeList": ["DELIVERY_TYPE_DELIVERY"]}})
    save("magnit_stores", stores)
    code = next(s for s in stores.json()["items"]["items"]
                if s["externalId"]["owner"] == "OWNER_MAGNIT")["externalId"]["storeCode"]
    save("magnit_store", api.post("v1/stores-facade/store",
                                  json={"externalId": {"owner": "OWNER_MAGNIT", "storeCode": code}}))
    for key, q in QUERIES.items():
        r = api.post("v2/goods/search", json={"storeType": "express", "catalogType": "2", "storeCode": code,
                                              "term": q, "pagination": {"limit": 10, "offset": 0},
                                              "sort": {"order": "desc", "type": "relevance"}})
        save(f"magnit_search_{key}", r)
    good = r.json()["items"][0]["id"]
    save("magnit_good", api.get(f"v2/goods/{good}/stores/{code}", params={"storetype": "express", "catalogtype": "2"}))
    # Другие форматы (гипермаркет, «Магнит Семейный»): какие пары storeType/catalogType существуют
    for st, ct in (("express", "1"), ("delivery", "1"), ("delivery", "2"), ("pickup", "1"), ("MM", "2")):
        r = api.post("v2/goods/search", json={"storeType": st, "catalogType": ct, "storeCode": code, "term": "молоко",
                                              "pagination": {"limit": 1, "offset": 0},
                                              "sort": {"order": "desc", "type": "relevance"}})
        save(f"magnit_pair_{st}_{ct}", {"status": r.status_code, "text": r.text[:600]})


def auchan():
    web = httpx.Client(timeout=30, follow_redirects=True, headers={
        "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148",
        "Accept": "application/json", "Referer": "https://www.auchan.ru/", "Origin": "https://www.auchan.ru"})
    shops = web.get("https://www.auchan.ru/v1/shops", params={"merchantId": 1}).json()
    save("auchan_shops", shops)
    save("auchan_regions", web.get("https://www.auchan.ru/v1/regions"))
    save("auchan_products_category", web.get("https://www.auchan.ru/v1/catalog/products", params={
        "merchantId": 1, "page": 1, "perPage": 5, "filter[category]": "moloko"}))
    bodies = [
        ("json_query", dict(json={"query": "молоко", "merchantId": 1, "page": 1, "perPage": 5})),
        ("json_q", dict(json={"q": "молоко", "merchantId": 1, "page": 1, "perPage": 5})),
        ("json_filter", dict(json={"filter": {"query": "молоко", "merchant_id": 1}, "page": 1, "perPage": 5})),
        ("form", dict(data={"query": "молоко", "merchantId": "1"})),
    ]
    for name, kw in bodies:
        save(f"auchan_search_{name}", web.post("https://www.auchan.ru/v1/search", params={"merchantId": 1}, **kw))
    for path in ("/v1/search/suggest", "/v1/search/products", "/v1/catalog/search", "/v1/autohints"):
        save("auchan_get" + path.replace("/", "_"),
             web.get("https://www.auchan.ru" + path, params={"query": "молоко", "merchantId": 1}))


def kuper():
    from curl_cffi import requests
    base = "https://web.kuper.ru"
    s = requests.Session(impersonate="chrome")
    s.get(f"{base}/?city_name=sankt-peterburg", timeout=30)
    headers = {"accept": "application/json", "referer": f"{base}/", "origin": base,
               "x-requested-with": "XMLHttpRequest"}
    r = s.get(f"{base}/api/v3/mweb/shelves?lat={SPB[0]}&lon={SPB[1]}&shelves_codes_to_exclude=alcohol",
              headers=headers, timeout=30)
    shelves = r.json()
    save("kuper_shelves", shelves)
    shop = ((shelves.get("data") or {}).get("shelves_data") or {}).get("shop") or {}
    stores = {(x.get("retailer") or {}).get("name"): x.get("id") for x in shop.values()}
    for name in ("Лента", "АШАН", "Магнит"):
        if name not in stores:
            continue
        for key, q in QUERIES.items():
            r = s.post(f"{base}/api/web/v1/products", data=json.dumps({"q": q, "store_id": str(stores[name])}),
                       headers={**headers, "content-type": "application/json"}, timeout=30)
            body = r.json() if r.status_code == 200 else {"text": r.text[:500]}
            if isinstance(body, dict) and "products" in body:
                body = {**body, "products": body["products"][:8]}
            save(f"kuper_{ {'Лента': 'lenta', 'АШАН': 'auchan', 'Магнит': 'magnit'}[name] }_{key}",
                 {"status": r.status_code, "body": body})


if __name__ == "__main__":
    for f in (lenta, magnit, auchan, kuper):
        guard(f)
