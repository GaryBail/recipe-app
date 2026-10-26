import XCTest
@testable import RecipeApp

final class RemotePriceProviderTests: XCTestCase {
    func testDecodeOffersFromServer() throws {
        let json = """
        {"offers": {
          "parmesan": {"offer": {"store_id": "perekrestok", "sku": "123", "title": "Сыр Пармезан 200г",
                                 "price": "399.90", "package_amount": 200, "unit": "g", "in_stock": true,
                                 "is_weighted": false, "regular_price": null, "image_url": null},
                       "cost": "399.90", "relevance": 1.0, "alternatives": []},
          "greek-tomatoes": {"offer": {"store_id": "perekrestok", "sku": "9", "title": "Томаты черри",
                                 "price": "450.00", "package_amount": 1000, "unit": "g", "in_stock": true,
                                 "is_weighted": true, "regular_price": "500.00", "image_url": null},
                       "cost": "135.00", "relevance": 1.0, "alternatives": []}
        }}
        """
        let offers = try RemotePriceProvider.decodeOffers(Data(json.utf8))
        XCTAssertEqual(offers["parmesan"]?.price, Decimal(string: "399.90"))
        XCTAssertEqual(offers["parmesan"]?.unit, .grams)
        XCTAssertEqual(offers["parmesan"]?.title, "Сыр Пармезан 200г")
        XCTAssertEqual(offers["greek-tomatoes"]?.isWeighted, true)
    }

    func testWeightedCostUsesExactAmount() {
        let line = CartLine(productId: "t", barcode: nil, title: "Томаты", requiredAmount: 300, unit: .grams)
        let offer = StoreOffer(productId: "t", price: 450, packageAmount: 1000, unit: .grams,
                               inStock: true, isWeighted: true)
        let quoteLine = QuoteLine(line: line, offer: offer, packages: 1)
        XCTAssertEqual(quoteLine.cost, 135)
    }

    func testSearchQueryDropsSeparator() {
        let line = CartLine(productId: "x", barcode: nil, title: "Спагетти №5 · Barilla",
                            requiredAmount: 200, unit: .grams)
        XCTAssertEqual(RemotePriceProvider.searchQuery(for: line), "Спагетти №5 Barilla")
    }

    func testFactoryFallsBackToMock() {
        XCTAssertTrue(PriceProviderFactory.make(serverURL: "") is MockPriceProvider)
        XCTAssertTrue(PriceProviderFactory.make(serverURL: "not a url") is MockPriceProvider)
        XCTAssertTrue(PriceProviderFactory.make(serverURL: "http://192.168.1.10:8000") is RemotePriceProvider)
    }
}
