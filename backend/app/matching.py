"""Подбор товара магазина под продукт из рецепта и расчёт стоимости."""

from __future__ import annotations

import math
import re
from decimal import ROUND_HALF_UP, Decimal

from .models import Match, Offer

# Сколько первых результатов поиска магазина рассматривать.
# Магазин сам сортирует по релевантности, поэтому дальние результаты чаще мимо.
TOP_RESULTS = 8
ALTERNATIVES = 3

_STOP_WORDS = {"для", "без", "или", "это", "при"}


def normalize(text: str) -> str:
    text = text.lower().replace("ё", "е")
    return re.sub(r"[^0-9a-zа-я]+", " ", text).strip()


def tokens(text: str) -> list[str]:
    return [t for t in normalize(text).split() if len(t) >= 3 and not t.isdigit() and t not in _STOP_WORDS]


def _stem(token: str) -> str:
    # Грубый стемминг для русского: отрезаем окончания.
    return token[:5] if len(token) > 5 else token


def relevance(query: str, title: str) -> float:
    """Доля слов запроса, найденных в названии товара (0..1)."""
    q = {_stem(t) for t in tokens(query)}
    if not q:
        return 0.0
    title_tokens = tokens(title)
    hits = sum(1 for s in q if any(t.startswith(s) for t in title_tokens))
    return hits / len(q)


def cost_for(offer: Offer, required_amount: float, unit: str) -> Decimal:
    """Стоимость покупки нужного количества: штучные — целыми упаковками, весовые — по весу."""
    if offer.unit != unit or offer.package_amount <= 0:
        return offer.price
    ratio = required_amount / offer.package_amount
    if offer.is_weighted:
        cost = offer.price * Decimal(str(ratio))
    else:
        cost = offer.price * max(1, math.ceil(ratio - 1e-9))
    return cost.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def best_match(query: str, offers: list[Offer], required_amount: float, unit: str) -> Match | None:
    """Из первых результатов поиска берём самые релевантные, среди них — самый дешёвый под нужное количество."""
    scored = [
        (relevance(query, o.title), o)
        for o in offers[:TOP_RESULTS]
        if o.in_stock
    ]
    scored = [(s, o) for s, o in scored if s >= 0.5]
    if not scored:
        return None

    top_score = max(s for s, _ in scored)
    candidates = [o for s, o in scored if s == top_score]
    same_unit = [o for o in candidates if o.unit == unit] or candidates
    ranked = sorted(same_unit, key=lambda o: cost_for(o, required_amount, unit))

    best = ranked[0]
    alternatives = [o for _, o in sorted(scored, key=lambda x: (-x[0], cost_for(x[1], required_amount, unit)))
                    if o.sku != best.sku][:ALTERNATIVES]
    return Match(offer=best, cost=cost_for(best, required_amount, unit),
                 relevance=top_score, alternatives=alternatives)
