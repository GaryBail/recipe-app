"""Разбор фасовки из названий товаров: "970мл", "1.5 л", "6 х 0.5 л", "10 шт"."""

from __future__ import annotations

import re

# единица в тексте -> (наша единица, множитель)
_UNITS: dict[str, tuple[str, float]] = {
    "кг": ("g", 1000),
    "гр": ("g", 1),
    "г": ("g", 1),
    "мл": ("ml", 1),
    "л": ("ml", 1000),
    "шт": ("pcs", 1),
}

_NUM = r"(\d+(?:[.,]\d+)?)"
_UNIT = r"(кг|гр|г|мл|л|шт)"
_MULTI_RE = re.compile(rf"(\d+)\s*[xх×*]\s*{_NUM}\s*{_UNIT}(?![а-яa-z])", re.IGNORECASE)
_SIZE_RE = re.compile(rf"{_NUM}\s*{_UNIT}(?![а-яa-z])", re.IGNORECASE)


def _to_float(s: str) -> float:
    return float(s.replace(",", "."))


def parse_size(text: str | None) -> tuple[float, str] | None:
    """Возвращает (количество, единица) по последнему упоминанию фасовки в тексте."""
    if not text:
        return None
    text = text.lower()

    multi = list(_MULTI_RE.finditer(text))
    if multi:
        count, amount, unit = multi[-1].groups()
        our_unit, k = _UNITS[unit]
        return int(count) * _to_float(amount) * k, our_unit

    found = list(_SIZE_RE.finditer(text))
    if not found:
        return None
    amount, unit = found[-1].groups()
    our_unit, k = _UNITS[unit]
    value = _to_float(amount) * k
    if value <= 0:
        return None
    return value, our_unit
