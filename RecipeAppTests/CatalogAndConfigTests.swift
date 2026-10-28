import SwiftData
import XCTest
@testable import RecipeApp

@MainActor
final class CatalogAndConfigTests: XCTestCase {
    /// Свойства категорий приходят из каталога, а не из списков в коде.
    func testCategoryMetadataFromSeed() {
        XCTAssertEqual(Catalog.departments.first, "Овощи и фрукты")
        XCTAssertEqual(Catalog.department(for: "potato").title, "Овощи и фрукты")
        XCTAssertEqual(Catalog.department(for: "fish-sauce").title, "Консервы, масла, соусы")
        XCTAssertEqual(Catalog.department(for: "user-cat-123").title, "Другое")
        XCTAssertTrue(Catalog.categories(tagged: "meat").contains("lamb"))
        XCTAssertTrue(Catalog.categories(tagged: "staple").contains("cumin"))
        XCTAssertTrue(Allergen.gluten.categories.contains("soy-sauce"))
        XCTAssertTrue(Allergen.nuts.categories.contains("nut-paste"))
        XCTAssertEqual(Catalog.category("hard-cheese")?.title, "Сыр твёрдый")
    }

    /// У каждой категории каталога есть название и отдел магазина.
    func testEveryCategoryHasDepartment() throws {
        let seed = try XCTUnwrap(Catalog.seed)
        let used = Set(seed.products.map(\.categoryId))
        for id in used {
            let info = try XCTUnwrap(Catalog.category(id), id)
            XCTAssertNotNil(info.department, id)
            XCTAssertFalse(info.title.isEmpty, id)
        }
    }

    /// Индекс даёт тот же типичный продукт, что и прежний перебор: первый по алфавиту с КБЖУ.
    func testNutritionIndexPicksFirstProductByName() {
        func product(_ id: String, _ name: String, nutrition: Bool = true) -> Product {
            let p = Product(id: id, name: name, brand: nil, categoryId: "cheese", barcode: nil)
            p.hasNutrition = nutrition
            p.kcal = 100
            return p
        }
        let index = NutritionIndex([product("b", "Пармезан"), product("a", "Грана Падано"),
                                    product("c", "Аааа без КБЖУ", nutrition: false)])
        XCTAssertEqual(index.typical["cheese"]?.id, "a")
    }

    func testServerURLParsing() {
        XCTAssertNil(AppConfig.url(from: ""))
        XCTAssertNil(AppConfig.url(from: "$(VV_SERVER_URL)"))
        XCTAssertNil(AppConfig.url(from: "not a url"))
        XCTAssertEqual(AppConfig.url(from: " https://api.vyborvkusa.ru ")?.host, "api.vyborvkusa.ru")
        XCTAssertTrue(AppConfig.allowsServerOverride)  // тестовая сборка
    }

    /// Версионированная схема открывается и сохраняет данные.
    func testVersionedContainerOpens() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = container.mainContext
        context.insert(ShoppingItem(title: "Молоко", categoryId: "milk", productId: nil, amount: 1000,
                                    unit: .milliliters, sources: ["Блины"]))
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ShoppingItem>()), 1)
        XCTAssertEqual(SchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
    }
}
