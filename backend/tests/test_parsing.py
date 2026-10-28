import json
from decimal import Decimal
from pathlib import Path

import pytest

from app.units import parse_size

FIXTURES = Path(__file__).parent / "fixtures"


def load(name):
    return json.loads((FIXTURES / name).read_text(encoding="utf-8"))


@pytest.mark.parametrize("text, expected", [
    ("Молоко 3.2% Пр!ст, 970мл", (970, "ml")),
    ("Напиток газированный 1.5 л", (1500, "ml")),
    ("Сыр Пармезан 40%, 200г", (200, "g")),
    ("Мука пшеничная 2 кг", (2000, "g")),
    ("Яйца куриные С0 10шт", (10, "pcs")),
    ("Вода 6 х 0,5 л", (3000, "ml")),
    ("Цена за 1 кг", (1000, "g")),
    ("Перец чёрный молотый", None),
    ("Масло 72.5% Простоквашино", None),
])
def test_parse_size(text, expected):
    assert parse_size(text) == expected
