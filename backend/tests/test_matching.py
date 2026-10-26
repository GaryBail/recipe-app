from decimal import Decimal

from app.matching import best_match, cost_for, relevance
from app.models import Offer


def offer(sku, title, price, amount, unit="g", weighted=False, in_stock=True):
    return Offer(store_id="s", sku=sku, title=title, price=Decimal(price),
                 package_amount=amount, unit=unit, in_stock=in_stock, is_weighted=weighted)


def test_relevance():
    assert relevance("Пармезан", "Сыр Пармезан 40% 200г") == 1.0
    assert relevance("Сметана 15%", "Сметана Простоквашино 15% 300г") == 1.0
    assert relevance("Спагетти Barilla", "Макароны Barilla Spaghetti n.5") == 0.5
    assert relevance("Пармезан", "Молоко 3.2%") == 0.0
    assert relevance("Перец чёрный молотый", "Перец черный молотый Kotanyi 20г") == 1.0  # ё == е


def test_cost_packages_and_weight():
    pack = offer("1", "Сыр 200г", "300", 200)
    assert cost_for(pack, 60, "g") == Decimal("300.00")
    assert cost_for(pack, 450, "g") == Decimal("900.00")

    tomatoes = offer("2", "Томаты", "250", 1000, weighted=True)
    assert cost_for(tomatoes, 300, "g") == Decimal("75.00")

    eggs = offer("3", "Яйца 10шт", "120", 10, unit="pcs")
    assert cost_for(eggs, 3, "pcs") == Decimal("120.00")

    # несовпадение единиц — одна упаковка
    onion = offer("4", "Лук", "60", 1000, weighted=True)
    assert cost_for(onion, 1, "pcs") == Decimal("60")


def test_best_match_prefers_relevance_then_cost():
    offers = [
        offer("a", "Сыр Пармезан 200г", "450", 200),
        offer("b", "Чипсы со вкусом сыра", "90", 100),
        offer("c", "Сыр Пармезан тёртый 100г", "260", 100),
        offer("d", "Сыр Пармезан 150г", "200", 150, in_stock=False),
    ]
    m = best_match("Пармезан", offers, 60, "g")
    assert m is not None
    assert m.offer.sku == "c"  # самый дешёвый на 60 г среди релевантных и в наличии
    assert m.cost == Decimal("260.00")
    assert [a.sku for a in m.alternatives] == ["a"]


def test_best_match_none_when_nothing_relevant():
    assert best_match("Пармезан", [offer("x", "Молоко 1л", "90", 1000, unit="ml")], 60, "g") is None


def test_best_match_only_looks_at_top_results():
    noise = [offer(str(i), "Молоко 1л", "90", 1000, unit="ml") for i in range(8)]
    late = offer("late", "Сыр Пармезан 200г", "300", 200)
    assert best_match("Пармезан", noise + [late], 60, "g") is None
