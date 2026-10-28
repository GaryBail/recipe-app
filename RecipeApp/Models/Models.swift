import Foundation
import SwiftData

/// Единица измерения количества ингредиента / фасовки товара.
enum MeasureUnit: String, Codable, CaseIterable, Sendable {
    case grams = "g"
    case milliliters = "ml"
    case pieces = "pcs"

    var short: String {
        switch self {
        case .grams: return "г"
        case .milliliters: return "мл"
        case .pieces: return "шт"
        }
    }
}

/// Рецепт блюда.
@Model
final class Recipe {
    @Attribute(.unique) var id: String
    var title: String
    var summary: String
    var servings: Int
    var steps: [String]
    /// Рецепт создан пользователем (можно удалить).
    var isUserCreated: Bool = false
    /// Рубрика каталога: breakfast, soup, salad, main, side, pastry, sauce.
    var rubric: String = ""
    /// Кухня: russian, italian, georgian… (пусто — своя без кухни).
    var cuisine: String = ""
    var cookMinutes: Int = 0
    /// Иллюстрация (RecipeApp/Resources/Food/food-<icon>.png).
    var icon: String = ""
    /// Показывать в «Популярном», пока нет данных о лайках с сервера.
    var featured: Bool = false
    /// В избранном (лайк). Хранится локально и синхронизируется с сервером после входа.
    var isFavorite: Bool = false
    var favoritedAt: Date? = nil

    @Relationship(deleteRule: .cascade, inverse: \Ingredient.recipe)
    var ingredients: [Ingredient] = []

    @Relationship(deleteRule: .cascade, inverse: \Build.recipe)
    var builds: [Build] = []

    init(id: String, title: String, summary: String, servings: Int, steps: [String]) {
        self.id = id
        self.title = title
        self.summary = summary
        self.servings = servings
        self.steps = steps
    }

    /// SwiftData не гарантирует порядок в массивах связей — сортируем по позиции.
    var sortedIngredients: [Ingredient] {
        ingredients.sorted { $0.position < $1.position }
    }
}

/// Ингредиент рецепта — это категория ("Сыр"), а не конкретный товар.
@Model
final class Ingredient {
    var id: String
    var title: String
    /// Категория, из которой пользователь выбирает конкретный продукт.
    var categoryId: String
    var amount: Double
    var unitRaw: String
    var position: Int
    var recipe: Recipe?

    init(id: String, title: String, categoryId: String, amount: Double, unit: MeasureUnit, position: Int) {
        self.id = id
        self.title = title
        self.categoryId = categoryId
        self.amount = amount
        self.unitRaw = unit.rawValue
        self.position = position
    }

    var unit: MeasureUnit { MeasureUnit(rawValue: unitRaw) ?? .pieces }

    var amountText: String { unit.format(amount) }

    /// Количество с учётом выбранного числа порций.
    func amountText(servings: Int) -> String {
        unit.format(scaledAmount(servings: servings))
    }

    func scaledAmount(servings: Int) -> Double {
        guard let base = recipe?.servings, base > 0, servings > 0 else { return amount }
        return amount * Double(servings) / Double(base)
    }
}

extension MeasureUnit {
    /// «250 г», «1,5 шт», «1,25 кг» — без лишних нулей. Штуки округляем до половинок.
    func format(_ amount: Double) -> String {
        switch self {
        case .pieces:
            return "\(Self.number(max(0.5, (amount * 2).rounded() / 2))) шт"
        case .grams:
            return amount >= 1000 ? "\(Self.number((amount / 10).rounded() / 100)) кг" : "\(Self.number(Self.small(amount))) г"
        case .milliliters:
            return amount >= 1000 ? "\(Self.number((amount / 10).rounded() / 100)) л" : "\(Self.number(Self.small(amount))) мл"
        }
    }

    private static func small(_ x: Double) -> Double { x >= 10 ? x.rounded() : (x * 10).rounded() / 10 }

    static func number(_ x: Double) -> String {
        if x.rounded() == x { return String(Int(x)) }
        return x.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "ru_RU")))
    }
}

/// Конкретный продукт из каталога ("Пармезан Galbani").
@Model
final class Product {
    @Attribute(.unique) var id: String
    var name: String
    var brand: String?
    var categoryId: String
    /// Штрихкод — самый надёжный способ сопоставить товар с ассортиментом магазина.
    var barcode: String?
    /// КБЖУ на 100 г (ориентировочно). hasNutrition = false — данных нет.
    var hasNutrition: Bool = false
    var kcal: Double = 0
    var protein: Double = 0
    var fat: Double = 0
    var carbs: Double = 0
    /// Вес одной штуки, г (для ингредиентов в штуках) и плотность, г/мл (для жидкостей).
    var gramsPerPiece: Double? = nil
    var density: Double? = nil

    init(id: String, name: String, brand: String?, categoryId: String, barcode: String?) {
        self.id = id
        self.name = name
        self.brand = brand
        self.categoryId = categoryId
        self.barcode = barcode
    }

    var displayName: String {
        if let brand, !brand.isEmpty { return "\(name) · \(brand)" }
        return name
    }
}

/// Сборка: рецепт + выбранный пользователем продукт для каждого ингредиента.
@Model
final class Build {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    /// Опубликована в сообществе.
    var isPublished: Bool
    /// id опубликованной копии на сервере.
    var remoteId: String? = nil
    /// Если сборка сохранена из сообщества — кто автор и откуда.
    var authorName: String? = nil
    var sourceRemoteId: String? = nil
    /// Включено слежение за ценой (подписка на сервере).
    var isWatched: Bool = false
    /// Сколько порций готовим по этой сборке (nil — как в рецепте).
    var servings: Int? = nil

    /// Порции сборки; количества продуктов пересчитываются пропорционально.
    var effectiveServings: Int { servings ?? recipe?.servings ?? 1 }
    var recipe: Recipe?

    @Relationship(deleteRule: .cascade, inverse: \BuildItem.build)
    var items: [BuildItem] = []

    init(name: String, recipe: Recipe) {
        self.id = UUID()
        self.name = name
        self.createdAt = .now
        self.isPublished = false
        self.recipe = recipe
    }

    /// ingredientId → productId
    var selection: [String: String] {
        Dictionary(items.compactMap { item in item.product.map { (item.ingredientId, $0.id) } },
                   uniquingKeysWith: { first, _ in first })
    }

    func product(for ingredient: Ingredient) -> Product? {
        items.first { $0.ingredientId == ingredient.id }?.product
    }

    /// Позиции корзины для сравнения цен.
    func cartLines() -> [CartLine] {
        guard let recipe else { return [] }
        return recipe.sortedIngredients.compactMap { ingredient in
            guard let product = product(for: ingredient) else { return nil }
            return CartLine(
                productId: product.id,
                barcode: product.barcode,
                title: product.displayName,
                requiredAmount: ingredient.scaledAmount(servings: effectiveServings),
                unit: ingredient.unit
            )
        }
    }
}

/// Строка сборки: ингредиент → выбранный продукт.
@Model
final class BuildItem {
    var ingredientId: String
    var product: Product?
    var build: Build?

    init(ingredientId: String, product: Product) {
        self.ingredientId = ingredientId
        self.product = product
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// Названия категорий берём из ингредиентов рецептов ("hard-cheese" → "Твёрдый сыр").
enum CategoryCatalog {
    /// Названия категорий каталога из seed.json («Сыр твёрдый», «Свежая зелень»).
    static let seedTitles: [String: String] = Dictionary(
        (SeedLoader.load()?.categories ?? []).map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })

    static func titles(ingredients: [Ingredient], products: [Product]) -> [(id: String, title: String)] {
        var map: [String: String] = [:]
        for id in Set(ingredients.map(\.categoryId)).union(products.map(\.categoryId)) {
            if let title = seedTitles[id] { map[id] = title }
        }
        for i in ingredients where map[i.categoryId] == nil { map[i.categoryId] = i.title }
        for p in products where map[p.categoryId] == nil { map[p.categoryId] = p.name }
        return map.map { (id: $0.key, title: $0.value) }
            .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
    }
}


/// Строка общего списка покупок. Собирается из сборок и рецептов; одинаковые продукты складываются.
@Model
final class ShoppingItem {
    @Attribute(.unique) var id: UUID
    /// Что купить: конкретный продукт («Пармезан · Galbani») или ингредиент («Твёрдый сыр»).
    var title: String
    var categoryId: String
    var productId: String?
    var amount: Double
    var unitRaw: String
    var isChecked: Bool = false
    var createdAt: Date
    /// Для каких рецептов («Борщ», «Плов»).
    var sources: [String] = []

    init(title: String, categoryId: String, productId: String?, amount: Double, unit: MeasureUnit, sources: [String]) {
        self.id = UUID()
        self.title = title
        self.categoryId = categoryId
        self.productId = productId
        self.amount = amount
        self.unitRaw = unit.rawValue
        self.createdAt = .now
        self.sources = sources
    }

    var unit: MeasureUnit { MeasureUnit(rawValue: unitRaw) ?? .pieces }
    var amountText: String { unit.format(amount) }
    /// Ключ для объединения одинаковых позиций.
    var mergeKey: String { ShoppingList.mergeKey(productId: productId, categoryId: categoryId, unit: unit) }
}
