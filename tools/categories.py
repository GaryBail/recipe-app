"""Свойства категорий продуктов — в одном месте.

Отсюда в seed.json попадают: отдел магазина (для списка покупок), аллергены, признаки
«мясо», «рыба», «животное» (для фильтров «Без мяса» и «Постное») и «всегда есть дома»
(для поиска «Из того, что есть»). Приложение читает их из каталога — списков в Swift нет.
Добавляя категорию, укажите её отдел здесь: генератор не пропустит категорию без отдела.
"""

DEPARTMENTS = ["Овощи и фрукты", "Молочное и яйца", "Мясо и колбасы", "Рыба", "Хлеб", "Бакалея",
               "Консервы, масла, соусы", "Специи", "Другое"]

_DEPARTMENT_CATS = {
    "Овощи и фрукты": """tomatoes cucumbers onion garlic carrot beetroot potato cabbage pumpkin mushrooms radish lettuce
        herbs lemon apples bell-pepper eggplant zucchini spinach leek fennel celery daikon avocado lime citrus ginger
        chili green-beans cauliflower napa-cabbage bean-sprouts shiitake tropical-fruit banana pear berries melon plums
        okra horseradish lemongrass""",
    "Молочное и яйца": """milk kefir cream sour-cream tvorog butter hard-cheese semi-hard-cheese feta suluguni
        processed-cheese eggs yogurt soft-cheese fresh-cheese mozzarella condensed-milk ice-cream ghee tofu kimchi""",
    "Мясо и колбасы": """beef pork minced-meat chicken-fillet chicken-thighs chicken-liver pork-cured sausage
        smoked-sausage frankfurters ham smoked-meat lamb veal rabbit chicken-whole pork-belly jamon pate bones
        animal-fat""",
    "Рыба": "salmon herring white-fish crab-sticks shrimp seafood",
    "Хлеб": "bread lavash bread-white tortillas dough-sheets",
    "Бакалея": """flour semolina oats buckwheat rice millet pearl-barley lentils split-peas spaghetti pasta-short noodles
        sugar yeast baking-powder cocoa raisins honey chocolate rice-paper noodles-rice noodles-wheat pasta-long bulgur
        chickpeas dry-beans corn-flour starch breadcrumbs biscuits rice-cakes gelatin nuts nut-paste sesame brown-sugar
        cocoa-chips dried-fruit milk-powder syrup bean-paste coffee-tea crackers dried-mushrooms seaweed""",
    "Консервы, масла, соусы": """pickles sauerkraut peas corn canned-beans canned-fish canned-tomatoes tomato-paste
        olives mayonnaise vinegar sunflower-oil olive-oil coconut-milk fish-sauce soy-sauce asian-sauces miso
        chili-paste ketchup mustard sesame-oil frying-oil pickled-veg hominy broth tamarind juice alcohol
        citrus-juice""",
    "Специи": """black-pepper paprika cumin coriander-seed turmeric spice-mix chili-powder warm-spices dried-herbs
        saffron vanilla seeds-spices""",
}

ALLERGENS = {
    "milk": """milk kefir cream sour-cream tvorog butter hard-cheese semi-hard-cheese feta suluguni processed-cheese
        sausage frankfurters chocolate yogurt soft-cheese fresh-cheese mozzarella condensed-milk milk-powder ice-cream
        ghee cocoa-chips""",
    "eggs": "eggs mayonnaise noodles pasta-long noodles-wheat",
    "gluten": """flour spaghetti pasta-short noodles bread semolina pearl-barley lavash oats sausage frankfurters
        crab-sticks pasta-long noodles-wheat bread-white breadcrumbs biscuits dough-sheets bulgur soy-sauce
        asian-sauces miso tortillas""",
    "fish": "salmon herring white-fish canned-fish fish-sauce seaweed",
    "seafood": "crab-sticks shrimp seafood",
    "nuts": "nuts nut-paste",
    "pork": "pork pork-cured smoked-meat ham minced-meat sausage smoked-sausage frankfurters pork-belly jamon pate animal-fat",
}

TAGS = {
    # мясо (и бульон на мясе) — нет в «Без мяса» и «Постном»
    "meat": """beef pork pork-cured minced-meat chicken-fillet chicken-thighs chicken-liver sausage smoked-sausage
        frankfurters ham smoked-meat lamb veal rabbit chicken-whole pork-belly jamon pate bones animal-fat broth""",
    "fish": "salmon herring white-fish canned-fish crab-sticks shrimp seafood fish-sauce",
    # молочное, яйца и прочее животное — нет в «Постном»
    "animal": """milk kefir cream sour-cream tvorog butter hard-cheese semi-hard-cheese feta suluguni processed-cheese
        eggs mayonnaise honey yogurt soft-cheese fresh-cheese mozzarella condensed-milk milk-powder ice-cream ghee
        gelatin""",
    # обычно есть дома — не спрашиваем в «Из того, что есть»
    "staple": """black-pepper paprika sunflower-oil olive-oil sugar vinegar baking-powder frying-oil cumin
        coriander-seed turmeric spice-mix chili-powder warm-spices dried-herbs seeds-spices vanilla""",
}


def _split(text: str) -> set[str]:
    return set(text.split())


def metadata(category_ids: set[str]) -> dict[str, dict]:
    """id → {department, allergens, tags}. Проверяет, что у каждой категории есть отдел и нет опечаток."""
    department = {}
    for title, cats in _DEPARTMENT_CATS.items():
        for cat in _split(cats):
            assert cat not in department, f"{cat}: два отдела"
            department[cat] = DEPARTMENTS.index(title)
    allergens = {a: _split(c) for a, c in ALLERGENS.items()}
    tags = {t: _split(c) for t, c in TAGS.items()}

    known = set(department) | set().union(*allergens.values()) | set().union(*tags.values())
    unknown = known - category_ids
    assert not unknown, f"в categories.py есть категории, которых нет в каталоге: {sorted(unknown)}"
    missing = category_ids - set(department)
    assert not missing, f"укажите отдел магазина для категорий: {sorted(missing)}"

    return {cat: {"department": department[cat],
                  "allergens": sorted(a for a, cats in allergens.items() if cat in cats),
                  "tags": sorted(t for t, cats in tags.items() if cat in cats)}
            for cat in sorted(category_ids)}
