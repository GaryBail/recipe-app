import Foundation

/// Подписка на цену сборки (сервер раз в несколько часов пересчитывает корзину).
struct WatchDTO: Decodable, Equatable, Sendable {
    struct StoreTotal: Decodable, Equatable, Sendable {
        let storeId: String
        let total: String
        let complete: Bool?
        let missing: Int?
    }

    let clientId: String
    let name: String
    let recipeTitle: String
    let cityId: String
    let checkedAt: String?
    let best: StoreTotal?
    let usualTotal: String?
    let stores: [StoreTotal]

    var bestTotal: Decimal? { best.flatMap { Decimal(string: $0.total) } }
    var usual: Decimal? { usualTotal.flatMap { Decimal(string: $0) } }

    var checkedDate: Date? {
        checkedAt.flatMap { ISO8601DateFormatter().date(from: $0) }
    }
}

struct WatchLineDTO: Encodable, Equatable {
    let productId: String
    let query: String
    let requiredAmount: Double
    let unit: String
}

struct WatchRequest: Encodable, Equatable {
    let name: String
    let recipeTitle: String
    let cityId: String
    let lines: [WatchLineDTO]
}

enum StoreNames {
    static func name(_ id: String) -> String {
        switch id {
        case "pyaterochka": return "Пятёрочка"
        case "perekrestok": return "Перекрёсток"
        default: return id
        }
    }
}

struct PriceWatchClient {
    static let supportedCity = "msk"

    let api: APIClient

    static func fromSettings() -> PriceWatchClient? {
        guard let api = APIClient.fromSettings(), api.token != nil else { return nil }
        return PriceWatchClient(api: api)
    }

    /// Состав сборки → подписка. id подписки = локальный id сборки.
    @MainActor
    static func request(for build: Build) -> WatchRequest? {
        let lines = build.cartLines().map {
            WatchLineDTO(productId: $0.productId, query: RemotePriceProvider.searchQuery(for: $0),
                         requiredAmount: $0.requiredAmount, unit: $0.unit.rawValue)
        }
        guard !lines.isEmpty, let recipe = build.recipe else { return nil }
        return WatchRequest(name: build.name, recipeTitle: recipe.title, cityId: supportedCity, lines: lines)
    }

    func upsert(id: String, _ request: WatchRequest) async throws -> WatchDTO {
        try await api.send("PUT", "watches/\(id)", body: request)
    }

    func get(id: String) async throws -> WatchDTO {
        try await api.send("GET", "watches/\(id)")
    }

    func delete(id: String) async throws {
        let _: APIClient.Empty = try await api.send("DELETE", "watches/\(id)")
    }

    /// После изменения состава сборки — обновить подписку, если она включена.
    @MainActor
    static func resyncIfWatched(_ build: Build) {
        guard build.isWatched, let client = fromSettings(), let request = request(for: build) else { return }
        let id = build.id.uuidString
        Task { _ = try? await client.upsert(id: id, request) }
    }
}
