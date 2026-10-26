import Foundation

/// Строка расчёта: сколько упаковок товара купить и за сколько.
struct QuoteLine: Hashable, Sendable {
    let line: CartLine
    let offer: StoreOffer
    let packages: Int

    var cost: Decimal { offer.price * Decimal(packages) }
}

/// Итог по одному магазину.
struct CartQuote: Identifiable, Hashable, Sendable {
    let store: Store
    let lines: [QuoteLine]
    let missing: [CartLine]
    let itemsTotal: Decimal
    let deliveryFee: Decimal
    /// Сколько не хватает до минимальной суммы заказа.
    let minOrderShortfall: Decimal

    var id: String { store.id }
    var total: Decimal { itemsTotal + deliveryFee }
    var isComplete: Bool { missing.isEmpty }
}

enum CartComparator {
    /// Сколько упаковок нужно, чтобы покрыть требуемое количество.
    /// Считаем целыми упаковками — так честнее для пользователя.
    static func packagesNeeded(required: Double, requiredUnit: MeasureUnit, offer: StoreOffer) -> Int {
        guard offer.unit == requiredUnit, offer.packageAmount > 0 else { return 1 }
        return max(1, Int((required / offer.packageAmount).rounded(.up)))
    }

    static func quote(lines: [CartLine], store: Store, offers: [String: StoreOffer]) -> CartQuote {
        var quoteLines: [QuoteLine] = []
        var missing: [CartLine] = []

        for line in lines {
            guard let offer = offers[line.productId], offer.inStock else {
                missing.append(line)
                continue
            }
            let packages = packagesNeeded(required: line.requiredAmount, requiredUnit: line.unit, offer: offer)
            quoteLines.append(QuoteLine(line: line, offer: offer, packages: packages))
        }

        let itemsTotal = quoteLines.reduce(Decimal.zero) { $0 + $1.cost }
        let delivery: Decimal
        if let free = store.freeDeliveryFrom, itemsTotal >= free {
            delivery = 0
        } else {
            delivery = store.deliveryFee
        }
        let shortfall = max(Decimal.zero, store.minOrder - itemsTotal)

        return CartQuote(store: store, lines: quoteLines, missing: missing,
                         itemsTotal: itemsTotal, deliveryFee: delivery,
                         minOrderShortfall: shortfall)
    }

    /// Сначала полные корзины, затем по итоговой цене (товары + доставка).
    /// Неполные — по числу недостающих позиций, затем по цене.
    static func rank(_ quotes: [CartQuote]) -> [CartQuote] {
        quotes.sorted { a, b in
            if a.isComplete != b.isComplete { return a.isComplete }
            if a.missing.count != b.missing.count { return a.missing.count < b.missing.count }
            return a.total < b.total
        }
    }
}

/// Опрашивает все магазины города параллельно и ранжирует корзины.
struct CartComparisonService: Sendable {
    let provider: any PriceProvider

    func compare(lines: [CartLine], in city: City) async throws -> [CartQuote] {
        let stores = try await provider.stores(in: city)
        let quotes = try await withThrowingTaskGroup(of: CartQuote.self) { group in
            for store in stores {
                group.addTask {
                    let offers = try await provider.offers(for: lines, in: store)
                    return CartComparator.quote(lines: lines, store: store, offers: offers)
                }
            }
            var result: [CartQuote] = []
            for try await quote in group { result.append(quote) }
            return result
        }
        return CartComparator.rank(quotes)
    }
}
