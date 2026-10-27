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
    /// Город, для которого получен магазин (нужен серверу при запросе цен).
    var cityId: String? = nil
    /// Пояснение к доставке, если точные условия неизвестны.
    var deliveryNote: String? = nil
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
    /// Название товара в магазине (что именно подобрано).
    var title: String? = nil
    /// Весовой товар: цена за packageAmount, покупается ровно нужное количество.
    var isWeighted: Bool = false
    /// Артикул товара в магазине — нужен, чтобы передать корзину в магазин.
    var sku: String? = nil
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
    /// Ссылка на готовую корзину в магазине (запрос к серверу). nil — магазин так не умеет.
    func cartLink(for quote: CartQuote) async throws -> URL?
}

extension PriceProvider {
    func cartLink(for quote: CartQuote) async throws -> URL? { cartDeepLink(for: quote) }
}

/// Что передаём в корзину магазина: артикул и количество (упаковки или килограммы для весового).
enum CartTransfer {
    static let stores: Set<String> = ["vkusvill"]

    static func items(for quote: CartQuote) -> [(sku: String, quantity: Double)] {
        quote.lines.compactMap { line in
            guard let sku = line.offer.sku else { return nil }
            if line.offer.isWeighted, line.offer.unit == line.line.unit, line.offer.packageAmount > 0 {
                // Килограммы с точностью до 10 г, округляя вверх (поправка на погрешность Double).
                let hundredths = (line.line.requiredAmount / line.offer.packageAmount * 100 - 1e-9).rounded(.up)
                return (sku, hundredths / 100)
            }
            return (sku, Double(line.packages))
        }
    }
}
