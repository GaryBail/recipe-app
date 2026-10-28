import Foundation
import SwiftData

// MARK: - «Из того, что есть»: обратный поиск рецептов по продуктам

enum FridgeMatcher {
    /// То, что почти всегда есть дома: не требуем отмечать.
    static let staples: Set<String> = ["black-pepper", "paprika", "sunflower-oil", "olive-oil", "sugar", "vinegar",
                                       "baking-powder", "frying-oil", "cumin", "coriander-seed", "turmeric",
                                       "spice-mix", "chili-powder", "warm-spices", "dried-herbs", "seeds-spices",
                                       "vanilla"]

    struct Result: Identifiable {
        let recipe: Recipe
        let have: [Ingredient]
        let missing: [Ingredient]
        var id: String { recipe.id }
        var total: Int { have.count + missing.count }
        var score: Double { total == 0 ? 0 : Double(have.count) / Double(total) }
        var isComplete: Bool { missing.isEmpty }
    }

    /// Рецепты, для которых есть хотя бы половина продуктов (или не хватает не больше двух),
    /// сначала те, где хватает всего.
    static func match(recipes: [Recipe], available: Set<String>, assumeStaples: Bool = true) -> [Result] {
        let have = assumeStaples ? available.union(staples) : available
        let results: [Result] = recipes.compactMap { recipe in
            let ingredients = recipe.sortedIngredients
            guard !ingredients.isEmpty else { return nil }
            let haveList = ingredients.filter { have.contains($0.categoryId) }
            let missing = ingredients.filter { !have.contains($0.categoryId) }
            // Нужен хотя бы один продукт из отмеченных, а не только «то, что всегда есть».
            guard haveList.contains(where: { available.contains($0.categoryId) }) else { return nil }
            let result = Result(recipe: recipe, have: haveList, missing: missing)
            return (result.score >= 0.5 || missing.count <= 2) ? result : nil
        }
        return results.sorted {
            if $0.missing.count != $1.missing.count { return $0.missing.count < $1.missing.count }
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.recipe.title.localizedCompare($1.recipe.title) == .orderedAscending
        }
    }

    /// Поиск категорий по введённому слову: «курица» → филе, бёдра, печень.
    static func categories(matching query: String, ingredients: [Ingredient], products: [Product]) -> [(id: String, title: String)] {
        let q = query.trimmed.lowercased()
        let all = CategoryCatalog.titles(ingredients: ingredients, products: products)
            .filter { !staples.contains($0.id) && !$0.id.hasPrefix("user-") }
        guard !q.isEmpty else { return all }
        let stem = String(q.prefix(max(3, q.count - 2)))  // «курица» → «кур», «молоко» → «моло»
        // Сначала совпадения в начале названия, потом внутри, потом по названиям продуктов.
        func rank(_ cat: (id: String, title: String)) -> Int? {
            let title = cat.title.lowercased()
            if title.hasPrefix(stem) { return 0 }
            if title.contains(stem) { return 1 }
            if products.contains(where: { $0.categoryId == cat.id && $0.name.lowercased().contains(stem) }) { return 2 }
            return nil
        }
        return all.compactMap { cat in rank(cat).map { (cat, $0) } }
            .sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.title < $1.0.title }
            .map { $0.0 }
    }
}

// MARK: - Подборки

struct RecipeCollection: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let palette: String
    let recipeIds: [String]

    /// Сезонные подборки: какая показывается — зависит от месяца.
    static func seasonal(for date: Date = .now, calendar: Calendar = .current) -> RecipeCollection {
        let month = calendar.component(.month, from: date)
        switch month {
        case 12, 1, 2:
            return RecipeCollection(id: "winter", title: "Зимнее меню", subtitle: "Сытно и празднично",
                                    icon: "pot-of-food", palette: "geekblue",
                                    recipeIds: ["borscht", "olivier", "herring-under-coat", "pelmeni", "solyanka",
                                                "pea-soup", "khachapuri", "golubtsy", "raisin-cake", "goulash"])
        case 3, 4, 5:
            return RecipeCollection(id: "spring", title: "Весна", subtitle: "Легче и свежее",
                                    icon: "leafy-green", palette: "green",
                                    recipeIds: ["shakshuka", "greek-salad", "summer-salad", "lentil-soup", "crab-salad",
                                                "baked-salmon", "fried-eggs", "cabbage-salad", "rice-vegetables",
                                                "lazy-vareniki"])
        case 6, 7, 8:
            return RecipeCollection(id: "summer", title: "Лето", subtitle: "Овощи с грядки и холодные супы",
                                    icon: "tomato", palette: "gold",
                                    recipeIds: ["okroshka", "summer-salad", "zucchini-fritters", "vegetable-stew",
                                                "ukha", "greek-salad", "stuffed-peppers", "baked-salmon",
                                                "beet-garlic-salad", "shawarma"])
        default:
            return RecipeCollection(id: "autumn", title: "Осень", subtitle: "Тыква, грибы и яблоки",
                                    icon: "brown-mushroom", palette: "orange",
                                    recipeIds: ["pumpkin-soup", "millet-porridge", "mushroom-soup", "charlotte",
                                                "baked-apples", "shchi", "rassolnik", "braised-cabbage",
                                                "fried-potatoes-mushrooms", "golubtsy", "cabbage-pies"])
        }
    }

    static let quick = RecipeCollection(id: "quick", title: "Быстро", subtitle: "До 30 минут", icon: "egg",
                                        palette: "cyan", recipeIds: [])
    static let lenten = RecipeCollection(id: "lenten", title: "Постное", subtitle: "Без мяса, молока и яиц",
                                         icon: "carrot", palette: "green", recipeIds: [])
    static let family = RecipeCollection(id: "family", title: "На всю семью", subtitle: "От 6 порций",
                                         icon: "shallow-pan-of-food", palette: "magenta", recipeIds: [])

    /// Номер недели года — по нему меняется «Подборка недели», пока нет данных о лайках.
    static func weekNumber(_ date: Date = .now, calendar: Calendar = .current) -> Int {
        calendar.component(.weekOfYear, from: date)
    }

    /// Рецепты подборки. Для «Хитов недели» — популярное с сервера, иначе 8 рецептов по номеру недели.
    func recipes(from all: [Recipe], popularIds: [String] = [], date: Date = .now) -> [Recipe] {
        let catalog = all.filter { !$0.isUserCreated }
        switch id {
        case "week":
            let byId = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let popular = popularIds.compactMap { byId[$0] }
            if popular.count >= 4 { return Array(popular.prefix(10)) }
            let sorted = catalog.sorted { $0.id < $1.id }
            guard !sorted.isEmpty else { return [] }
            let start = (Self.weekNumber(date) * 7) % sorted.count
            return (0..<min(8, sorted.count)).map { sorted[(start + $0 * 9) % sorted.count] }
                .reduce(into: [Recipe]()) { acc, r in if !acc.contains(where: { $0.id == r.id }) { acc.append(r) } }
        case "quick":
            return catalog.filter(RecipeTraits.isQuick).sorted { $0.cookMinutes < $1.cookMinutes }
        case "lenten":
            return catalog.filter(RecipeTraits.isLenten)
        case "family":
            return catalog.filter { $0.servings >= 6 }
        default:
            let byId = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            return recipeIds.compactMap { byId[$0] }
        }
    }

    static func all(date: Date = .now) -> [RecipeCollection] {
        [RecipeCollection(id: "week", title: "Хиты недели", subtitle: "Что готовят чаще всего",
                          icon: "cooking", palette: "volcano", recipeIds: []),
         seasonal(for: date), quick, lenten, family]
    }
}

// MARK: - Таймеры в шагах рецепта

enum StepTimer {
    private static let regex = try! NSRegularExpression(
        pattern: #"(\d+(?:[.,]\d+)?)(?:\s*[–—-]\s*(\d+(?:[.,]\d+)?))?\s*(час(?:а|ов)?|ч\b|минут[аы]?|мин\b|секунд)"#,
        options: [.caseInsensitive])

    /// Время из текста шага: «варите 20 минут» → 1200 с, «1–1,5 часа» → 5400 с (берём верхнюю границу),
    /// несколько упоминаний — самое долгое.
    static func duration(in text: String) -> TimeInterval? {
        let range = NSRange(text.startIndex..., in: text)
        var best: TimeInterval?
        for m in regex.matches(in: text, range: range) {
            func number(_ i: Int) -> Double? {
                guard let r = Range(m.range(at: i), in: text) else { return nil }
                return Double(text[r].replacingOccurrences(of: ",", with: "."))
            }
            guard let low = number(1), let unitRange = Range(m.range(at: 3), in: text) else { continue }
            let value = number(2) ?? low
            let unit = text[unitRange].lowercased()
            let seconds: Double
            if unit.hasPrefix("ч") { seconds = value * 3600 }
            else if unit.hasPrefix("сек") { seconds = value }
            else { seconds = value * 60 }
            guard seconds > 0, seconds <= 12 * 3600 else { continue }
            best = max(best ?? 0, seconds)
        }
        return best
    }

    static func format(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.up))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}

// MARK: - Список покупок

/// Позиция для добавления в список (до объединения с тем, что уже есть).
struct ShoppingEntry: Hashable, Sendable {
    let title: String
    let categoryId: String
    let productId: String?
    let amount: Double
    let unit: MeasureUnit
    let source: String
}

enum ShoppingList {
    static func mergeKey(productId: String?, categoryId: String, unit: MeasureUnit) -> String {
        "\(productId ?? "cat:\(categoryId)")|\(unit.rawValue)"
    }

    /// Продукты сборки с учётом её порций.
    static func entries(for build: Build) -> [ShoppingEntry] {
        guard let recipe = build.recipe else { return [] }
        return recipe.sortedIngredients.map { ingredient in
            let product = build.product(for: ingredient)
            return ShoppingEntry(title: product?.displayName ?? ingredient.title, categoryId: ingredient.categoryId,
                                 productId: product?.id,
                                 amount: ingredient.scaledAmount(servings: build.effectiveServings),
                                 unit: ingredient.unit, source: recipe.title)
        }
    }

    /// Ингредиенты рецепта без выбранных продуктов (по названиям из рецепта).
    static func entries(for recipe: Recipe, servings: Int) -> [ShoppingEntry] {
        recipe.sortedIngredients.map {
            ShoppingEntry(title: $0.title, categoryId: $0.categoryId, productId: nil,
                          amount: $0.scaledAmount(servings: servings), unit: $0.unit, source: recipe.title)
        }
    }

    /// Добавляет позиции: одинаковые продукты (или ингредиенты одной категории) складываются,
    /// уже купленная позиция снова становится некупленной.
    @MainActor
    static func add(_ entries: [ShoppingEntry], to existing: [ShoppingItem], context: ModelContext) {
        var byKey = Dictionary(existing.map { ($0.mergeKey, $0) }, uniquingKeysWith: { a, _ in a })
        for entry in entries {
            let key = mergeKey(productId: entry.productId, categoryId: entry.categoryId, unit: entry.unit)
            if let item = byKey[key] {
                item.amount = item.isChecked ? entry.amount : item.amount + entry.amount
                item.isChecked = false
                if !item.sources.contains(entry.source) { item.sources.append(entry.source) }
            } else {
                let item = ShoppingItem(title: entry.title, categoryId: entry.categoryId, productId: entry.productId,
                                        amount: entry.amount, unit: entry.unit, sources: [entry.source])
                context.insert(item)
                byKey[key] = item
            }
        }
        try? context.save()
    }

    /// Отделы магазина — так удобнее идти по залу.
    static func department(for categoryId: String) -> (order: Int, title: String) {
        switch categoryId {
        case "tomatoes", "cucumbers", "onion", "garlic", "carrot", "beetroot", "potato", "cabbage", "pumpkin",
             "mushrooms", "radish", "lettuce", "herbs", "lemon", "apples", "bell-pepper", "eggplant", "zucchini",
             "spinach", "leek", "fennel", "celery", "daikon", "avocado", "lime", "citrus", "ginger", "chili",
             "green-beans", "cauliflower", "napa-cabbage", "bean-sprouts", "shiitake", "tropical-fruit", "banana",
             "pear", "berries", "melon", "plums", "okra", "horseradish", "lemongrass":
            return (0, "Овощи и фрукты")
        case "milk", "kefir", "cream", "sour-cream", "tvorog", "butter", "hard-cheese", "semi-hard-cheese", "feta",
             "suluguni", "processed-cheese", "eggs", "yogurt", "soft-cheese", "fresh-cheese", "mozzarella",
             "condensed-milk", "ice-cream", "ghee", "tofu", "kimchi":
            return (1, "Молочное и яйца")
        case "beef", "pork", "minced-meat", "chicken-fillet", "chicken-thighs", "chicken-liver", "pork-cured",
             "sausage", "smoked-sausage", "frankfurters", "ham", "smoked-meat", "lamb", "veal", "rabbit",
             "chicken-whole", "pork-belly", "jamon", "pate", "bones", "animal-fat":
            return (2, "Мясо и колбасы")
        case "salmon", "herring", "white-fish", "crab-sticks", "shrimp", "seafood":
            return (3, "Рыба")
        case "bread", "lavash", "bread-white", "tortillas", "dough-sheets":
            return (4, "Хлеб")
        case "flour", "semolina", "oats", "buckwheat", "rice", "millet", "pearl-barley", "lentils", "split-peas",
             "spaghetti", "pasta-short", "noodles", "sugar", "yeast", "baking-powder", "cocoa", "raisins", "honey",
             "chocolate", "rice-paper", "noodles-rice", "noodles-wheat", "pasta-long", "bulgur", "chickpeas",
             "dry-beans", "corn-flour", "starch", "breadcrumbs", "biscuits", "rice-cakes", "gelatin", "nuts",
             "nut-paste", "sesame", "brown-sugar", "cocoa-chips", "dried-fruit", "milk-powder", "syrup",
             "bean-paste", "coffee-tea", "crackers", "dried-mushrooms", "seaweed":
            return (5, "Бакалея")
        case "pickles", "sauerkraut", "peas", "corn", "canned-beans", "canned-fish", "canned-tomatoes",
             "tomato-paste", "olives", "mayonnaise", "vinegar", "sunflower-oil", "olive-oil", "coconut-milk",
             "fish-sauce", "soy-sauce", "asian-sauces", "miso", "chili-paste", "ketchup", "mustard", "sesame-oil",
             "frying-oil", "pickled-veg", "hominy", "broth", "tamarind", "juice", "alcohol", "citrus-juice":
            return (6, "Консервы, масла, соусы")
        case "black-pepper", "paprika", "cumin", "coriander-seed", "turmeric", "spice-mix", "chili-powder",
             "warm-spices", "dried-herbs", "saffron", "vanilla", "seeds-spices":
            return (7, "Специи")
        default:
            return (8, "Другое")
        }
    }

    static func shareText(_ items: [ShoppingItem]) -> String {
        let open = items.filter { !$0.isChecked }
        var lines = ["🛒 Список покупок", ""]
        let groups = Dictionary(grouping: open) { department(for: $0.categoryId).title }
        for title in groups.keys.sorted(by: { department(forTitle: $0) < department(forTitle: $1) }) {
            lines.append(title + ":")
            for item in groups[title]!.sorted(by: { $0.title < $1.title }) {
                lines.append("☐ \(item.title) — \(item.amountText)")
            }
            lines.append("")
        }
        lines.append("Собрано в приложении «ВыборВкуса»")
        return lines.joined(separator: "\n")
    }

    private static func department(forTitle title: String) -> Int {
        ["Овощи и фрукты", "Молочное и яйца", "Мясо и колбасы", "Рыба", "Хлеб", "Бакалея",
         "Консервы, масла, соусы", "Специи", "Другое"].firstIndex(of: title) ?? 99
    }
}
