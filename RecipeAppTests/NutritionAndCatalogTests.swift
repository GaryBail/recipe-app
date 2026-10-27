import UIKit
import SwiftData
import XCTest
@testable import RecipeApp

@MainActor
final class NutritionAndCatalogTests: XCTestCase {
    private func container() throws -> ModelContainer {
        try ModelContainer(for: Recipe.self, Ingredient.self, Product.self, Build.self, BuildItem.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func product(_ id: String, kcal: Double, p: Double, f: Double, c: Double,
                         piece: Double? = nil, density: Double? = nil, category: String = "x") -> Product {
        let product = Product(id: id, name: id, brand: nil, categoryId: category, barcode: nil)
        product.hasNutrition = true
        product.kcal = kcal
        product.protein = p
        product.fat = f
        product.carbs = c
        product.gramsPerPiece = piece
        product.density = density
        return product
    }

    func testGramsMillilitersAndPieces() {
        let cheese = product("cheese", kcal: 400, p: 30, f: 30, c: 0)
        let oil = product("oil", kcal: 900, p: 0, f: 100, c: 0, density: 0.92)
        let egg = product("egg", kcal: 157, p: 12.7, f: 11.5, c: 0.7, piece: 50)

        XCTAssertEqual(NutritionCalculator.nutrition(of: cheese, amount: 50, unit: .grams)?.kcal, 200)
        XCTAssertEqual(NutritionCalculator.nutrition(of: oil, amount: 100, unit: .milliliters)?.kcal ?? 0, 828, accuracy: 0.01)
        XCTAssertEqual(NutritionCalculator.nutrition(of: egg, amount: 2, unit: .pieces)?.kcal ?? 0, 157, accuracy: 0.01)

        // штуки без веса штуки посчитать нельзя
        let noWeight = product("onion", kcal: 41, p: 1, f: 0, c: 8)
        XCTAssertNil(NutritionCalculator.nutrition(of: noWeight, amount: 1, unit: .pieces))
    }

    func testSummaryPerServingAndPer100g() {
        let cheese = product("cheese", kcal: 400, p: 30, f: 30, c: 0)
        let pasta = product("pasta", kcal: 350, p: 12, f: 1.5, c: 70)
        let summary = NutritionCalculator.summary([
            NutritionLine(title: "Сыр", amount: 100, unit: .grams, product: cheese),
            NutritionLine(title: "Паста", amount: 200, unit: .grams, product: pasta),
            NutritionLine(title: "Соль", amount: 5, unit: .grams, product: nil),
        ])
        XCTAssertEqual(summary.total.kcal, 1100, accuracy: 0.01)
        XCTAssertEqual(summary.grams, 300)
        XCTAssertEqual(summary.perServing(2).kcal, 550, accuracy: 0.01)
        XCTAssertEqual(summary.per100g?.kcal ?? 0, 366.67, accuracy: 0.01)
        XCTAssertEqual(summary.missing, ["Соль"])
    }

    func testCatalogSeedsAndUpgradesWithoutTouchingUserData() throws {
        let container = try container()
        let context = container.mainContext
        let defaults = UserDefaults(suiteName: "test-\(UUID())")!
        let bundle = Bundle(for: RecipeAppTestsBundleMarker.self)
        let appBundle = Bundle.main.url(forResource: "seed", withExtension: "json") != nil ? Bundle.main : bundle

        // старая установка: рецепт карбонары без новых полей и своя сборка на нём
        let old = Recipe(id: "carbonara", title: "Старое название", summary: "", servings: 2, steps: [])
        context.insert(old)
        let ing = Ingredient(id: "carbonara-cheese", title: "Сыр", categoryId: "hard-cheese", amount: 50, unit: .grams, position: 0)
        ing.recipe = old
        context.insert(ing)
        let mine = Recipe(id: "user-1", title: "Мой рецепт", summary: "", servings: 1, steps: [])
        mine.isUserCreated = true
        context.insert(mine)
        try context.save()
        defaults.set(1, forKey: SeedLoader.versionKey)

        SeedLoader.sync(context, bundle: appBundle, defaults: defaults)

        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        XCTAssertEqual(recipes.count, 25)  // 24 из каталога + свой
        let carbonara = try XCTUnwrap(recipes.first { $0.id == "carbonara" })
        XCTAssertEqual(carbonara.title, "Паста карбонара")
        XCTAssertEqual(carbonara.rubric, "main")
        XCTAssertTrue(carbonara.featured)
        XCTAssertEqual(carbonara.ingredients.first { $0.id == "carbonara-cheese" }?.amount, 60)
        XCTAssertEqual(carbonara.ingredients.count, 5)
        XCTAssertEqual(recipes.first { $0.id == "user-1" }?.title, "Мой рецепт")

        let products = try context.fetch(FetchDescriptor<Product>())
        XCTAssertTrue(products.allSatisfy(\.hasNutrition))

        // повторный запуск той же версии ничего не дублирует
        SeedLoader.sync(context, bundle: appBundle, defaults: defaults)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Recipe>()), 25)

        // у всех рецептов каталога КБЖУ считается полностью
        for recipe in recipes where !recipe.isUserCreated {
            let s = NutritionCalculator.recipeSummary(recipe, products: products)
            XCTAssertTrue(s.missing.isEmpty, "\(recipe.title): нет данных для \(s.missing)")
            XCTAssertGreaterThan(s.perServing(recipe.servings).kcal, 50, recipe.title)
        }
    }

    func testRubricsLoaded() {
        XCTAssertEqual(Rubric.all.map(\.id), ["breakfast", "soup", "salad", "main", "side", "pastry"])
        XCTAssertEqual(Rubric.named("soup")?.title, "Супы")
    }

    func testDecodeSocialDTOs() throws {
        let json = """
        [{"recipe_id": "plov", "likes": 3, "recent_likes": 2,
          "cover": {"id": "p1", "recipe_id": "plov", "author_id": "u", "author_name": "Алиса", "width": 1600,
                    "height": 1067, "url": "/media/photos/p1.jpg", "thumb_url": "/media/photos/p1_thumb.jpg",
                    "created_at": "2026-10-27T10:00:00+00:00"}}]
        """
        let popular = try APIClient.decoder.decode([PopularDTO].self, from: Data(json.utf8))
        XCTAssertEqual(popular.first?.cover?.thumbUrl, "/media/photos/p1_thumb.jpg")

        let api = APIClient(baseURL: URL(string: "https://api.example.ru")!, token: nil)
        XCTAssertEqual(api.mediaURL("/media/photos/p1.jpg")?.absoluteString, "https://api.example.ru/media/photos/p1.jpg")
    }

    func testPhotoPreparationDownscales() throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4000, height: 3000),
                                               format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
        let big = renderer.jpegData(withCompressionQuality: 0.9) { ctx in
            UIColor.orange.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 4000, height: 3000))
        }
        let jpeg = try XCTUnwrap(PhotoPreparation.jpeg(from: big))
        let image = try XCTUnwrap(UIImage(data: jpeg))
        XCTAssertEqual(max(image.size.width, image.size.height), 2048)
    }
}

private final class RecipeAppTestsBundleMarker {}
