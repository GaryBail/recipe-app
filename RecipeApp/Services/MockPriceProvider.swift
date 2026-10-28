import Foundation

/// Тестовый источник с вымышленными магазинами и детерминированными ценами.
/// Нужен, чтобы отлаживать логику и интерфейс, пока нет реального источника данных.
struct MockPriceProvider: PriceProvider {
    private static let allCities = [
        City(id: "spb", name: "Санкт-Петербург"),
        City(id: "msk", name: "Москва"),
        City(id: "kzn", name: "Казань")
    ]

    /// Наценка магазина в процентах — чтобы цены отличались между магазинами.
    private static let storeMarkup: [String: Int] = ["a": 100, "b": 92, "c": 110]

    func cities() async throws -> [City] { Self.allCities }

    func stores(in city: City) async throws -> [Store] {
        var stores = [
            Store(id: "a", name: "Магазин А", deliveryFee: 199, freeDeliveryFrom: 2000, minOrder: 500,
                  appScheme: "storea", appStoreURL: nil, webURL: URL(string: "https://example.com/a")),
            Store(id: "b", name: "Магазин Б", deliveryFee: 299, freeDeliveryFrom: nil, minOrder: 1000,
                  appScheme: "storeb", appStoreURL: nil, webURL: URL(string: "https://example.com/b"))
        ]
        if city.id == "spb" {
            stores.append(Store(id: "c", name: "Магазин В", deliveryFee: 0, freeDeliveryFrom: nil, minOrder: 1500,
                                appScheme: "storec", appStoreURL: nil, webURL: URL(string: "https://example.com/c")))
        }
        return stores
    }

    func offers(for lines: [CartLine], in store: Store) async throws -> [String: StoreOffer] {
        try await Task.sleep(nanoseconds: 300_000_000) // имитация сети
        var result: [String: StoreOffer] = [:]
        let markup = Self.storeMarkup[store.id] ?? 100

        for line in lines {
            let h = Self.stableHash(line.productId + store.id)
            // Примерно каждый 9-й товар отсутствует в магазине.
            if h % 9 == 0 { continue }

            let package: Double
            switch line.unit {
            case .grams: package = [100, 200, 250, 400, 500, 1000][h % 6]
            case .milliliters: package = [250, 500, 1000][h % 3]
            case .pieces: package = [1, 6, 10][h % 3]
            }
            let base = 60 + Self.stableHash(line.productId) % 400
            let price = Decimal(base * markup / 100)

            result[line.productId] = StoreOffer(productId: line.productId, price: price,
                                                packageAmount: package, unit: line.unit, inStock: true)
        }
        return result
    }

    func cartDeepLink(for quote: CartQuote) -> URL? { nil }

    /// hashValue в Swift меняется между запусками — для стабильных цен нужен свой хеш.
    private static func stableHash(_ s: String) -> Int {
        s.unicodeScalars.reduce(5381) { ($0 &* 33 &+ Int($1.value)) & 0x7fff_ffff }
    }
}
