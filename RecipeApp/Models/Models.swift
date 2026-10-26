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

    var amountText: String {
        let value = amount.rounded() == amount ? String(Int(amount)) : String(amount)
        return "\(value) \(unit.short)"
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
    /// Задел под этап 2 (публикация в сообщество).
    var isPublished: Bool
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
                requiredAmount: ingredient.amount,
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
