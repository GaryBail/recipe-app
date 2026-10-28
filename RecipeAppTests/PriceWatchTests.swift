import XCTest
import SwiftData
@testable import RecipeApp

@MainActor
final class PriceWatchTests: XCTestCase {
    func testDecodeWatch() throws {
        let json = """
        {"client_id": "abc", "name": "Моя карбонара", "recipe_title": "Паста карбонара", "city_id": "spb",
         "updated_at": "2026-10-27T10:00:00+00:00", "checked_at": "2026-10-27T15:00:00+00:00",
         "best": {"store_id": "lenta", "total": "412.50"}, "usual_total": "480.00",
         "stores": [{"store_id": "lenta", "total": "412.50", "complete": true, "missing": 0},
                    {"store_id": "magnit", "total": "455.00", "complete": true, "missing": 0}]}
        """
        let watch = try APIClient.decoder.decode(WatchDTO.self, from: Data(json.utf8))
        XCTAssertEqual(watch.bestTotal, Decimal(string: "412.50"))
        XCTAssertEqual(watch.usual, 480)
        XCTAssertEqual(watch.stores.count, 2)
        XCTAssertNotNil(watch.checkedDate)
        XCTAssertEqual(StoreNames.name(watch.best!.storeId), "Лента")
    }

    func testWatchRequestFromBuild() throws {
        let container = try ModelContainer(
            for: Recipe.self, Ingredient.self, Product.self, Build.self, BuildItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let recipe = Recipe(id: "r", title: "Паста карбонара", summary: "", servings: 2, steps: [])
        context.insert(recipe)
        let ingredient = Ingredient(id: "r-0", title: "Спагетти", categoryId: "spaghetti", amount: 200,
                                    unit: .grams, position: 0)
        ingredient.recipe = recipe
        context.insert(ingredient)
        let product = Product(id: "spaghetti-barilla", name: "Спагетти №5", brand: "Barilla",
                              categoryId: "spaghetti", barcode: nil)
        context.insert(product)
        let build = Build(name: "Моя", recipe: recipe)
        context.insert(build)
        let item = BuildItem(ingredientId: "r-0", product: product)
        item.build = build
        context.insert(item)
        try context.save()

        let request = try XCTUnwrap(PriceWatchClient.request(for: build))
        XCTAssertEqual(request.cityId, "spb")
        XCTAssertEqual(request.recipeTitle, "Паста карбонара")
        XCTAssertEqual(request.lines, [WatchLineDTO(productId: "spaghetti-barilla", query: "Спагетти №5 Barilla",
                                                    requiredAmount: 200, unit: "g")])
        let json = String(decoding: try APIClient.encoder.encode(request), as: UTF8.self)
        XCTAssertTrue(json.contains("\"required_amount\"") && json.contains("\"recipe_title\""))
    }

    func testOldSavedAccountStillDecodes() throws {
        // Профиль, сохранённый прошлой версией приложения (без новых полей).
        let old = #"{"id":"u1","email":"a@b.ru","displayName":"А","cityId":null,"hasApple":false,"hasPassword":true}"#
        let account = try JSONDecoder().decode(AccountDTO.self, from: Data(old.utf8))
        XCTAssertFalse(account.isEmailVerified)
        XCTAssertTrue(account.priceAlertsOn)
    }

    func testPriceNotificationRouting() throws {
        XCTAssertEqual(PushRegistration.localBuildId(from: ["kind": "reminder", "local_build_id": "B-1"]), "B-1")
        XCTAssertNil(PushRegistration.localBuildId(from: ["build_id": "x"]))

        let json = """
        {"id": 1, "kind": "price_drop", "build_id": "B-1", "build_name": "Моя", "actor_name": "Рецепты",
         "stars": null, "comment": null, "title": "Подешевело", "body": "…", "created_at": "2026-10-27T10:00:00+00:00",
         "is_read": false}
        """
        let item = try APIClient.decoder.decode(AppNotificationDTO.self, from: Data(json.utf8))
        XCTAssertTrue(item.isPrice)
    }
}
