import Foundation
import SwiftData

/// Стартовый каталог из seed.json. При выходе новой версии каталога недостающие рецепты и продукты
/// добавляются, а существующие обновляются (КБЖУ, тексты); рецепты пользователя не трогаются.
enum SeedLoader {
    static let versionKey = "seedVersion"

    struct SeedFile: Decodable {
        let version: Int?
        let rubrics: [Rubric]?
        let cuisines: [Cuisine]?
        let categories: [CategoryInfo]?
        let departments: [String]?
        let products: [ProductDTO]
        let recipes: [RecipeDTO]
    }

    struct NutritionDTO: Decodable {
        let kcal: Double
        let protein: Double
        let fat: Double
        let carbs: Double
    }

    struct ProductDTO: Decodable {
        let id: String
        let name: String
        let brand: String?
        let categoryId: String
        let barcode: String?
        let nutrition: NutritionDTO?
        let gramsPerPiece: Double?
        let density: Double?
    }

    struct RecipeDTO: Decodable {
        let id: String
        let title: String
        let summary: String
        let servings: Int
        let steps: [String]
        let ingredients: [IngredientDTO]
        let category: String?
        let cookMinutes: Int?
        let featured: Bool?
        let icon: String?
        let cuisine: String?
    }

    struct IngredientDTO: Decodable {
        let id: String
        let title: String
        let categoryId: String
        let amount: Double
        let unit: MeasureUnit
    }

    static func decode(_ data: Data) throws -> SeedFile {
        try JSONDecoder().decode(SeedFile.self, from: data)
    }

    static func load(bundle: Bundle = .main) -> SeedFile? {
        guard let url = bundle.url(forResource: "seed", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? decode(data)
    }

    /// Старое имя — оставлено для совместимости.
    @MainActor
    static func seedIfNeeded(_ context: ModelContext, bundle: Bundle = .main) {
        sync(context, bundle: bundle)
    }

    @MainActor
    static func sync(_ context: ModelContext, bundle: Bundle = .main, defaults: UserDefaults = .standard) {
        guard let seed = load(bundle: bundle) else { return }
        let version = seed.version ?? 1
        let recipeCount = (try? context.fetchCount(FetchDescriptor<Recipe>())) ?? 0
        guard recipeCount == 0 || version > defaults.integer(forKey: versionKey) else { return }
        apply(seed, to: context)
        defaults.set(version, forKey: versionKey)
    }

    @MainActor
    static func apply(_ seed: SeedFile, to context: ModelContext) {
        let products = Dictionary(((try? context.fetch(FetchDescriptor<Product>())) ?? []).map { ($0.id, $0) },
                                  uniquingKeysWith: { a, _ in a })
        for p in seed.products {
            let product = products[p.id] ?? {
                let new = Product(id: p.id, name: p.name, brand: p.brand, categoryId: p.categoryId, barcode: p.barcode)
                context.insert(new)
                return new
            }()
            product.name = p.name
            product.brand = p.brand
            product.categoryId = p.categoryId
            if let n = p.nutrition {
                product.hasNutrition = true
                product.kcal = n.kcal
                product.protein = n.protein
                product.fat = n.fat
                product.carbs = n.carbs
            }
            product.gramsPerPiece = p.gramsPerPiece
            product.density = p.density
        }

        let recipes = Dictionary(((try? context.fetch(FetchDescriptor<Recipe>())) ?? []).map { ($0.id, $0) },
                                 uniquingKeysWith: { a, _ in a })
        for r in seed.recipes {
            let recipe: Recipe
            if let existing = recipes[r.id] {
                guard !existing.isUserCreated else { continue }
                recipe = existing
                recipe.title = r.title
                recipe.summary = r.summary
                recipe.servings = r.servings
                recipe.steps = r.steps
            } else {
                recipe = Recipe(id: r.id, title: r.title, summary: r.summary, servings: r.servings, steps: r.steps)
                context.insert(recipe)
            }
            recipe.rubric = r.category ?? recipe.rubric
            recipe.cookMinutes = r.cookMinutes ?? recipe.cookMinutes
            recipe.featured = r.featured ?? false
            recipe.icon = r.icon ?? recipe.icon
            recipe.cuisine = r.cuisine ?? recipe.cuisine

            // Ингредиенты обновляем по id: на них ссылаются сборки пользователя.
            let current = Dictionary(recipe.ingredients.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            for (index, i) in r.ingredients.enumerated() {
                if let ingredient = current[i.id] {
                    ingredient.title = i.title
                    ingredient.categoryId = i.categoryId
                    ingredient.amount = i.amount
                    ingredient.unitRaw = i.unit.rawValue
                    ingredient.position = index
                } else {
                    let ingredient = Ingredient(id: i.id, title: i.title, categoryId: i.categoryId,
                                                amount: i.amount, unit: i.unit, position: index)
                    ingredient.recipe = recipe
                    context.insert(ingredient)
                }
            }
        }

        try? context.save()
    }
}

/// Рубрика каталога («Супы», «Салаты»…).
struct Rubric: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
    let icon: String?

    static var all: [Rubric] { Catalog.rubrics }

    static func named(_ id: String) -> Rubric? { all.first { $0.id == id } }
}

/// Кухня мира («Итальянская», «Японская»…).
struct Cuisine: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let icon: String

    static var all: [Cuisine] { Catalog.cuisines }

    static func named(_ id: String) -> Cuisine? { all.first { $0.id == id } }
}
