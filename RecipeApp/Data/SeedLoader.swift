import Foundation
import SwiftData

/// Загружает стартовый каталог (рецепты и продукты) из seed.json при первом запуске.
enum SeedLoader {
    struct SeedFile: Decodable {
        let products: [ProductDTO]
        let recipes: [RecipeDTO]
    }

    struct ProductDTO: Decodable {
        let id: String
        let name: String
        let brand: String?
        let categoryId: String
        let barcode: String?
    }

    struct RecipeDTO: Decodable {
        let id: String
        let title: String
        let summary: String
        let servings: Int
        let steps: [String]
        let ingredients: [IngredientDTO]
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

    @MainActor
    static func seedIfNeeded(_ context: ModelContext, bundle: Bundle = .main) {
        let existing = (try? context.fetchCount(FetchDescriptor<Recipe>())) ?? 0
        guard existing == 0,
              let url = bundle.url(forResource: "seed", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let seed = try? decode(data)
        else { return }

        for p in seed.products {
            context.insert(Product(id: p.id, name: p.name, brand: p.brand,
                                   categoryId: p.categoryId, barcode: p.barcode))
        }

        for r in seed.recipes {
            let recipe = Recipe(id: r.id, title: r.title, summary: r.summary,
                                servings: r.servings, steps: r.steps)
            context.insert(recipe)
            for (index, i) in r.ingredients.enumerated() {
                let ingredient = Ingredient(id: i.id, title: i.title, categoryId: i.categoryId,
                                            amount: i.amount, unit: i.unit, position: index)
                ingredient.recipe = recipe
                context.insert(ingredient)
            }
        }

        try? context.save()
    }
}
