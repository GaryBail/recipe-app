import XCTest
@testable import RecipeApp

final class CartComparatorTests: XCTestCase {
    private let cheese = CartLine(productId: "parmesan", barcode: nil, title: "Пармезан",
                                  requiredAmount: 100, unit: .grams)
    private let eggs = CartLine(productId: "eggs", barcode: nil, title: "Яйца",
                                requiredAmount: 3, unit: .pieces)

    private func store(id: String, fee: Decimal = 100, freeFrom: Decimal? = nil, minOrder: Decimal = 0) -> Store {
        Store(id: id, name: id, deliveryFee: fee, freeDeliveryFrom: freeFrom, minOrder: minOrder,
              appScheme: nil, appStoreURL: nil, webURL: nil)
    }

    private func offer(_ id: String, price: Decimal, pack: Double, unit: MeasureUnit, inStock: Bool = true) -> StoreOffer {
        StoreOffer(productId: id, price: price, packageAmount: pack, unit: unit, inStock: inStock)
    }

    func testPackagesRoundUp() {
        XCTAssertEqual(CartComparator.packagesNeeded(required: 100, requiredUnit: .grams,
                                                     offer: offer("x", price: 1, pack: 250, unit: .grams)), 1)
        XCTAssertEqual(CartComparator.packagesNeeded(required: 400, requiredUnit: .grams,
                                                     offer: offer("x", price: 1, pack: 250, unit: .grams)), 2)
        XCTAssertEqual(CartComparator.packagesNeeded(required: 3, requiredUnit: .pieces,
                                                     offer: offer("x", price: 1, pack: 10, unit: .pieces)), 1)
    }

    func testQuoteTotalsDeliveryAndMinOrder() {
        let quote = CartComparator.quote(
            lines: [cheese, eggs],
            store: store(id: "a", fee: 199, minOrder: 1000),
            offers: [
                "parmesan": offer("parmesan", price: 300, pack: 200, unit: .grams),
                "eggs": offer("eggs", price: 120, pack: 10, unit: .pieces)
            ])
        XCTAssertTrue(quote.isComplete)
        XCTAssertEqual(quote.itemsTotal, 420)
        XCTAssertEqual(quote.total, 619)
        XCTAssertEqual(quote.minOrderShortfall, 580)
    }

    func testFreeDelivery() {
        let quote = CartComparator.quote(
            lines: [cheese],
            store: store(id: "a", fee: 199, freeFrom: 300),
            offers: ["parmesan": offer("parmesan", price: 300, pack: 200, unit: .grams)])
        XCTAssertEqual(quote.deliveryFee, 0)
    }

    func testMissingAndOutOfStock() {
        let quote = CartComparator.quote(
            lines: [cheese, eggs],
            store: store(id: "a"),
            offers: ["parmesan": offer("parmesan", price: 300, pack: 200, unit: .grams, inStock: false)])
        XCTAssertEqual(quote.missing.count, 2)
        XCTAssertFalse(quote.isComplete)
    }

    func testRankingPrefersCompleteThenCheapest() {
        let offers = [
            "parmesan": offer("parmesan", price: 300, pack: 200, unit: .grams),
            "eggs": offer("eggs", price: 120, pack: 10, unit: .pieces)
        ]
        let expensive = CartComparator.quote(lines: [cheese, eggs], store: store(id: "exp", fee: 500), offers: offers)
        let cheap = CartComparator.quote(lines: [cheese, eggs], store: store(id: "cheap", fee: 0), offers: offers)
        let incomplete = CartComparator.quote(lines: [cheese, eggs], store: store(id: "inc", fee: 0),
                                              offers: ["eggs": offers["eggs"]!])

        let ranked = CartComparator.rank([incomplete, expensive, cheap]).map(\.store.id)
        XCTAssertEqual(ranked, ["cheap", "exp", "inc"])
    }

    func testSeedFileDecodes() throws {
        let url = try XCTUnwrap(Bundle(for: RecipeAppTestsMarker.self).url(forResource: "seed", withExtension: "json")
                                ?? Bundle.main.url(forResource: "seed", withExtension: "json"))
        let seed = try SeedLoader.decode(Data(contentsOf: url))
        XCTAssertEqual(seed.recipes.count, 24)
        XCTAssertTrue(seed.products.allSatisfy { $0.nutrition != nil }, "у всех продуктов есть КБЖУ")

        // У каждого ингредиента должен быть хотя бы один продукт в его категории.
        let categories = Set(seed.products.map(\.categoryId))
        for recipe in seed.recipes {
            for ingredient in recipe.ingredients {
                XCTAssertTrue(categories.contains(ingredient.categoryId),
                              "Нет продуктов для категории \(ingredient.categoryId)")
            }
        }
    }
}

private final class RecipeAppTestsMarker {}
