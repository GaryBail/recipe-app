import Foundation

/// Город пользователя — от него зависит список магазинов с доставкой.
struct City: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
}

/// Магазин с доставкой в выбранном городе.
struct Store: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let deliveryFee: Decimal
    /// Сумма, от которой доставка бесплатная (если есть).
    let freeDeliveryFrom: Decimal?
    let minOrder: Decimal
    /// URL-схема приложения магазина (без "://"). Должна быть в LSApplicationQueriesSchemes.
    let appScheme: String?
    let appStoreURL: URL?
    let webURL: URL?
}

/// Позиция корзины: что нужно купить для сборки.
struct CartLine: Hashable, Sendable {
    let productId: String
    let barcode: String?
    let title: String
    let requiredAmount: Double
    let unit: MeasureUnit
}

/// Предложение магазина по конкретному продукту.
struct StoreOffer: Hashable, Sendable {
    let productId: String
    let price: Decimal
    /// Фасовка товара в магазине (например, 250 г).
    let packageAmount: Double
    let unit: MeasureUnit
    let inStock: Bool
}

/// Источник цен и магазинов. Для каждого реального источника (партнёрский API,
/// агрегатор доставки и т.д.) пишется свой адаптер с этим интерфейсом —
/// остальное приложение от источника не зависит.
protocol PriceProvider: Sendable {
    func cities() async throws -> [City]
    func stores(in city: City) async throws -> [Store]
    /// Предложения магазина по позициям корзины, ключ — productId.
    func offers(for lines: [CartLine], in store: Store) async throws -> [String: StoreOffer]
    /// Deep link, который сразу открывает корзину в приложении магазина, если магазин это поддерживает.
    func cartDeepLink(for quote: CartQuote) -> URL?
}
