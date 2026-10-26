import Foundation

// MARK: - DTO (JSON сервера в snake_case, конвертируем автоматически)

struct CommunityIngredientDTO: Codable, Hashable, Sendable {
    let id: String
    let title: String
    let categoryId: String
    let amount: Double
    let unit: String
}

struct CommunityRecipeDTO: Codable, Hashable, Sendable {
    let id: String
    let title: String
    let summary: String
    let servings: Int
    let steps: [String]
    let ingredients: [CommunityIngredientDTO]
}

struct CommunityProductDTO: Codable, Hashable, Sendable {
    let id: String
    let name: String
    let brand: String?
    let categoryId: String
    let barcode: String?

    var displayName: String {
        if let brand, !brand.isEmpty { return "\(name) · \(brand)" }
        return name
    }
}

struct CommunityItemDTO: Codable, Hashable, Sendable {
    let ingredientId: String
    let product: CommunityProductDTO
}

struct PublishBuildRequest: Codable, Sendable {
    let authorName: String
    let name: String
    let recipe: CommunityRecipeDTO
    let items: [CommunityItemDTO]
}

struct CommunityBuildDTO: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let authorId: String
    let authorName: String
    let name: String
    let createdAt: String
    let recipe: CommunityRecipeDTO
    let items: [CommunityItemDTO]
    let ratingAvg: Double?
    let ratingCount: Int
    let score: Double
    let myRating: Int?

    func product(forIngredient id: String) -> CommunityProductDTO? {
        items.first { $0.ingredientId == id }?.product
    }

    /// Позиции корзины — чтобы сравнить цены чужой сборки, не сохраняя её.
    var cartLines: [CartLine] {
        recipe.ingredients.compactMap { ingredient in
            guard let product = product(forIngredient: ingredient.id) else { return nil }
            return CartLine(productId: product.id, barcode: product.barcode, title: product.displayName,
                            requiredAmount: ingredient.amount,
                            unit: MeasureUnit(rawValue: ingredient.unit) ?? .pieces)
        }
    }
}

struct CommunityRatingDTO: Codable, Hashable, Sendable {
    let userId: String
    let authorName: String
    let stars: Int
    let comment: String?
    let createdAt: String
}

// MARK: - Пользователь

/// Анонимный идентификатор устройства. Для App Store заменить на Sign in with Apple.
enum UserIdentity {
    static let idKey = "userId"
    static let nameKey = "displayName"

    static var id: String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: idKey) { return existing }
        let new = UUID().uuidString.lowercased()
        defaults.set(new, forKey: idKey)
        return new
    }

    static var displayName: String {
        let name = UserDefaults.standard.string(forKey: nameKey)?.trimmed ?? ""
        return name.isEmpty ? "Аноним" : name
    }
}

// MARK: - Клиент

struct CommunityClient: Sendable {
    let baseURL: URL
    let userId: String
    var session: URLSession = .shared

    enum Sort: String, CaseIterable, Identifiable {
        case top, new
        var id: String { rawValue }
        var title: String { self == .top ? "Лучшие" : "Новые" }
    }

    enum ClientError: LocalizedError {
        case status(Int, String?)
        var errorDescription: String? {
            switch self {
            case .status(let code, let detail): return detail ?? "Ошибка сервера (\(code))"
            }
        }
    }

    /// nil, если адрес сервера не указан в настройках.
    static func fromSettings() -> CommunityClient? {
        let raw = UserDefaults.standard.string(forKey: PriceProviderFactory.serverURLKey)?.trimmed ?? ""
        guard let url = URL(string: raw), url.scheme?.hasPrefix("http") == true, url.host != nil else { return nil }
        return CommunityClient(baseURL: url, userId: UserIdentity.id)
    }

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    func builds(recipeId: String? = nil, sort: Sort = .top, mine: Bool = false) async throws -> [CommunityBuildDTO] {
        var query = [URLQueryItem(name: "sort", value: sort.rawValue)]
        if let recipeId { query.append(URLQueryItem(name: "recipe_id", value: recipeId)) }
        if mine { query.append(URLQueryItem(name: "mine", value: "true")) }
        return try await send("GET", "community/builds", query: query)
    }

    func build(id: String) async throws -> CommunityBuildDTO {
        try await send("GET", "community/builds/\(id)")
    }

    func publish(_ request: PublishBuildRequest) async throws -> CommunityBuildDTO {
        try await send("POST", "community/builds", body: request)
    }

    func delete(id: String) async throws {
        let _: Empty = try await send("DELETE", "community/builds/\(id)")
    }

    func ratings(buildId: String) async throws -> [CommunityRatingDTO] {
        try await send("GET", "community/builds/\(buildId)/ratings")
    }

    func rate(buildId: String, stars: Int, comment: String?) async throws -> CommunityBuildDTO {
        struct Body: Encodable { let stars: Int; let comment: String?; let authorName: String }
        return try await send("PUT", "community/builds/\(buildId)/rating",
                              body: Body(stars: stars, comment: comment, authorName: UserIdentity.displayName))
    }

    func report(buildId: String, reason: String) async throws {
        struct Body: Encodable { let reason: String }
        let _: Empty = try await send("POST", "community/builds/\(buildId)/report", body: Body(reason: reason))
    }

    func block(userId blocked: String) async throws {
        struct Body: Encodable { let userId: String }
        let _: Empty = try await send("POST", "community/blocks", body: Body(userId: blocked))
    }

    // MARK: - HTTP

    private struct Empty: Decodable {}
    private struct NoBody: Encodable {}
    private struct ErrorBody: Decodable { let detail: String? }

    private func send<T: Decodable>(_ method: String, _ path: String, query: [URLQueryItem] = []) async throws -> T {
        try await send(method, path, query: query, body: Optional<NoBody>.none)
    }

    private func send<T: Decodable, B: Encodable>(_ method: String, _ path: String,
                                                  query: [URLQueryItem] = [], body: B?) async throws -> T {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue(userId, forHTTPHeaderField: "X-User-Id")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try Self.encoder.encode(body)
        }

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let detail = try? JSONDecoder().decode(ErrorBody.self, from: data).detail
            throw ClientError.status(status, detail)
        }
        if T.self == Empty.self { return Empty() as! T }
        return try Self.decoder.decode(T.self, from: data)
    }
}
