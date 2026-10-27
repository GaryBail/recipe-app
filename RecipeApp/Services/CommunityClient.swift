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

// MARK: - Клиент

struct CommunityClient: Sendable {
    let api: APIClient

    enum Sort: String, CaseIterable, Identifiable {
        case top, new
        var id: String { rawValue }
        var title: String { self == .top ? "Лучшие" : "Новые" }
    }

    /// nil, если адрес сервера не указан в настройках.
    static func fromSettings() -> CommunityClient? {
        APIClient.fromSettings().map(CommunityClient.init(api:))
    }

    static var encoder: JSONEncoder { APIClient.encoder }
    static var decoder: JSONDecoder { APIClient.decoder }

    func builds(recipeId: String? = nil, sort: Sort = .top, mine: Bool = false) async throws -> [CommunityBuildDTO] {
        var query = [URLQueryItem(name: "sort", value: sort.rawValue)]
        if let recipeId { query.append(URLQueryItem(name: "recipe_id", value: recipeId)) }
        if mine { query.append(URLQueryItem(name: "mine", value: "true")) }
        return try await api.send("GET", "community/builds", query: query)
    }

    func build(id: String) async throws -> CommunityBuildDTO {
        try await api.send("GET", "community/builds/\(id)")
    }

    func publish(_ request: PublishBuildRequest) async throws -> CommunityBuildDTO {
        try await api.send("POST", "community/builds", body: request)
    }

    func delete(id: String) async throws {
        let _: APIClient.Empty = try await api.send("DELETE", "community/builds/\(id)")
    }

    func ratings(buildId: String) async throws -> [CommunityRatingDTO] {
        try await api.send("GET", "community/builds/\(buildId)/ratings")
    }

    func rate(buildId: String, stars: Int, comment: String?) async throws -> CommunityBuildDTO {
        struct Body: Encodable { let stars: Int; let comment: String? }
        return try await api.send("PUT", "community/builds/\(buildId)/rating",
                                  body: Body(stars: stars, comment: comment))
    }

    func report(buildId: String, reason: String) async throws {
        struct Body: Encodable { let reason: String }
        let _: APIClient.Empty = try await api.send("POST", "community/builds/\(buildId)/report",
                                                    body: Body(reason: reason))
    }

    func block(userId blocked: String) async throws {
        struct Body: Encodable { let userId: String }
        let _: APIClient.Empty = try await api.send("POST", "community/blocks", body: Body(userId: blocked))
    }
}
