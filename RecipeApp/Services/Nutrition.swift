import Foundation

/// Калории, белки, жиры, углеводы.
struct Nutrition: Equatable, Sendable {
    var kcal: Double = 0
    var protein: Double = 0
    var fat: Double = 0
    var carbs: Double = 0

    static let zero = Nutrition()

    static func + (a: Nutrition, b: Nutrition) -> Nutrition {
        Nutrition(kcal: a.kcal + b.kcal, protein: a.protein + b.protein, fat: a.fat + b.fat, carbs: a.carbs + b.carbs)
    }

    func scaled(_ k: Double) -> Nutrition {
        Nutrition(kcal: kcal * k, protein: protein * k, fat: fat * k, carbs: carbs * k)
    }

    /// «323 ккал · Б 23 · Ж 17 · У 20»
    var shortText: String {
        "\(Int(kcal.rounded())) ккал · Б \(Int(protein.rounded())) · Ж \(Int(fat.rounded())) · У \(Int(carbs.rounded()))"
    }
}

/// Типичный продукт каждой категории — строится один раз на весь список рецептов,
/// чтобы КБЖУ карточек не перебирало все продукты для каждого ингредиента.
struct NutritionIndex {
    let typical: [String: Product]

    init(_ products: [Product]) {
        var best: [String: Product] = [:]
        for product in products where product.hasNutrition {
            if let current = best[product.categoryId],
               current.name.localizedCompare(product.name) != .orderedDescending { continue }
            best[product.categoryId] = product
        }
        typical = best
    }

    func summary(for recipe: Recipe) -> NutritionSummary {
        NutritionCalculator.summary(recipe.sortedIngredients.map {
            NutritionLine(title: $0.title, amount: $0.amount, unit: $0.unit, product: typical[$0.categoryId])
        })
    }

    /// Калорийность порции; nil — посчитать не удалось.
    func kcalPerServing(_ recipe: Recipe) -> Double? {
        let s = summary(for: recipe)
        return s.grams > 0 ? s.perServing(recipe.servings).kcal : nil
    }
}

/// Строка для расчёта: сколько чего и какой продукт.
struct NutritionLine {
    let title: String
    let amount: Double
    let unit: MeasureUnit
    let product: Product?
}

struct NutritionSummary: Equatable {
    var total: Nutrition
    /// Вес всех продуктов с известным КБЖУ, г (по сырым продуктам).
    var grams: Double
    /// Ингредиенты, для которых посчитать не удалось.
    var missing: [String]

    func perServing(_ servings: Int) -> Nutrition { total.scaled(1 / Double(max(servings, 1))) }

    var per100g: Nutrition? { grams > 0 ? total.scaled(100 / grams) : nil }
}

enum NutritionCalculator {
    /// Количество в граммах: граммы как есть, миллилитры через плотность, штуки через вес штуки.
    static func grams(amount: Double, unit: MeasureUnit, product: Product) -> Double? {
        switch unit {
        case .grams: return amount
        case .milliliters: return amount * (product.density ?? 1)
        case .pieces: return product.gramsPerPiece.map { amount * $0 }
        }
    }

    static func nutrition(of product: Product, amount: Double, unit: MeasureUnit) -> Nutrition? {
        guard product.hasNutrition, let g = grams(amount: amount, unit: unit, product: product) else { return nil }
        return Nutrition(kcal: product.kcal, protein: product.protein, fat: product.fat, carbs: product.carbs)
            .scaled(g / 100)
    }

    static func summary(_ lines: [NutritionLine]) -> NutritionSummary {
        var result = NutritionSummary(total: .zero, grams: 0, missing: [])
        for line in lines {
            guard let product = line.product,
                  let g = grams(amount: line.amount, unit: line.unit, product: product),
                  let n = nutrition(of: product, amount: line.amount, unit: line.unit) else {
                result.missing.append(line.title)
                continue
            }
            result.total = result.total + n
            result.grams += g
        }
        return result
    }

    /// Типичный продукт для ингредиента рецепта (до того, как пользователь выбрал свой).
    static func typicalProduct(for ingredient: Ingredient, in products: [Product]) -> Product? {
        NutritionIndex(products).typical[ingredient.categoryId]
    }

    static func recipeSummary(_ recipe: Recipe, products: [Product]) -> NutritionSummary {
        NutritionIndex(products).summary(for: recipe)
    }

    static func buildSummary(_ build: Build) -> NutritionSummary {
        guard let recipe = build.recipe else { return NutritionSummary(total: .zero, grams: 0, missing: []) }
        return summary(recipe.sortedIngredients.map {
            NutritionLine(title: $0.title, amount: $0.amount, unit: $0.unit, product: build.product(for: $0))
        })
    }
}
