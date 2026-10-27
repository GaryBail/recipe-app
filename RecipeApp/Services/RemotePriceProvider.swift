import Foundation

/// Источник цен через наш сервер (backend/), который опрашивает магазины.
struct RemotePriceProvider: PriceProvider {
    let baseURL: URL
    var session: URLSession = .shared

    enum RemoteError: LocalizedError {
        case badStatus(Int)
        var errorDescription: String? {
            switch self {
            case .badStatus(let code): return "Сервер ответил с ошибкой \(code)"
            }
        }
    }

    // MARK: - DTO (ключи как в JSON сервера)

    struct CityDTO: Decodable { let id: String; let name: String }

    struct StoreDTO: Decodable {
        let id: String
        let name: String
        let deliveryFee: String
        let freeDeliveryFrom: String?
        let minOrder: String
        let deliveryNote: String?
        let appScheme: String?
        let appStoreURL: String?
        let webURL: String?

        enum CodingKeys: String, CodingKey {
            case id, name
            case deliveryFee = "delivery_fee"
            case freeDeliveryFrom = "free_delivery_from"
            case minOrder = "min_order"
            case deliveryNote = "delivery_note"
            case appScheme = "app_scheme"
            case appStoreURL = "app_store_url"
            case webURL = "web_url"
        }
    }

    struct OfferDTO: Decodable {
        let sku: String
        let title: String
        let price: String
        let packageAmount: Double
        let unit: String
        let inStock: Bool
        let isWeighted: Bool

        enum CodingKeys: String, CodingKey {
            case sku, title, price, unit
            case packageAmount = "package_amount"
            case inStock = "in_stock"
            case isWeighted = "is_weighted"
        }
    }

    struct MatchDTO: Decodable { let offer: OfferDTO }
    struct OffersResponse: Decodable { let offers: [String: MatchDTO] }

    struct LineDTO: Encodable {
        let productId: String
        let query: String
        let requiredAmount: Double
        let unit: String

        enum CodingKeys: String, CodingKey {
            case query, unit
            case productId = "product_id"
            case requiredAmount = "required_amount"
        }
    }

    struct OffersRequest: Encodable {
        let store: String
        let city: String
        let lines: [LineDTO]
    }

    // MARK: - PriceProvider

    func cities() async throws -> [City] {
        let dto: [CityDTO] = try await get("cities")
        return dto.map { City(id: $0.id, name: $0.name) }
    }

    func stores(in city: City) async throws -> [Store] {
        let dto: [StoreDTO] = try await get("stores", query: [URLQueryItem(name: "city", value: city.id)])
        return dto.map { s in
            Store(id: s.id, name: s.name,
                  deliveryFee: Decimal(string: s.deliveryFee) ?? 0,
                  freeDeliveryFrom: s.freeDeliveryFrom.flatMap { Decimal(string: $0) },
                  minOrder: Decimal(string: s.minOrder) ?? 0,
                  appScheme: s.appScheme,
                  appStoreURL: s.appStoreURL.flatMap(URL.init(string:)),
                  webURL: s.webURL.flatMap(URL.init(string:)),
                  cityId: city.id,
                  deliveryNote: s.deliveryNote)
        }
    }

    func offers(for lines: [CartLine], in store: Store) async throws -> [String: StoreOffer] {
        let body = OffersRequest(
            store: store.id,
            city: store.cityId ?? "",
            lines: lines.map {
                LineDTO(productId: $0.productId, query: Self.searchQuery(for: $0),
                        requiredAmount: $0.requiredAmount, unit: $0.unit.rawValue)
            })
        var request = URLRequest(url: baseURL.appendingPathComponent("offers"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        request.timeoutInterval = 120 // первый запрос к магазину прогревает браузер на сервере
        let data = try await load(request)
        return try Self.decodeOffers(data)
    }

    func cartDeepLink(for quote: CartQuote) -> URL? { nil }

    struct CartItemDTO: Encodable { let sku: String; let quantity: Double }
    struct CartLinkRequest: Encodable { let store: String; let items: [CartItemDTO] }
    struct CartLinkResponse: Decodable { let url: String }

    func cartLink(for quote: CartQuote) async throws -> URL? {
        guard CartTransfer.stores.contains(quote.store.id) else { return nil }
        let items = CartTransfer.items(for: quote).map { CartItemDTO(sku: $0.sku, quantity: $0.quantity) }
        guard !items.isEmpty else { return nil }
        var request = URLRequest(url: baseURL.appendingPathComponent("cart-link"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(CartLinkRequest(store: quote.store.id, items: items))
        request.timeoutInterval = 30
        let response = try JSONDecoder().decode(CartLinkResponse.self, from: try await load(request))
        return URL(string: response.url)
    }

    // MARK: - Helpers

    /// "Спагетти №5 · Barilla" → "Спагетти №5 Barilla"
    static func searchQuery(for line: CartLine) -> String {
        line.title.replacingOccurrences(of: " · ", with: " ")
    }

    static func decodeOffers(_ data: Data) throws -> [String: StoreOffer] {
        let response = try JSONDecoder().decode(OffersResponse.self, from: data)
        var result: [String: StoreOffer] = [:]
        for (productId, match) in response.offers {
            let o = match.offer
            guard let price = Decimal(string: o.price) else { continue }
            result[productId] = StoreOffer(productId: productId, price: price,
                                           packageAmount: o.packageAmount,
                                           unit: MeasureUnit(rawValue: o.unit) ?? .pieces,
                                           inStock: o.inStock, title: o.title,
                                           isWeighted: o.isWeighted, sku: o.sku)
        }
        return result
    }

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 120
        return try JSONDecoder().decode(T.self, from: try await load(request))
    }

    private func load(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw RemoteError.badStatus(http.statusCode)
        }
        return data
    }
}

/// Выбор источника цен: сервер, если указан адрес, иначе тестовые данные.
enum PriceProviderFactory {
    static let serverURLKey = "priceServerURL"

    static func make(serverURL: String) -> any PriceProvider {
        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true, url.host != nil {
            return RemotePriceProvider(baseURL: url)
        }
        return MockPriceProvider()
    }
}
