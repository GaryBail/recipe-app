import UIKit

/// Решает, куда отправить пользователя после выбора магазина.
enum StoreLauncher {
    enum Destination: Equatable {
        /// Приложение магазина установлено.
        case app(URL)
        /// Не установлено — предлагаем скачать.
        case appStore(URL)
        /// Нет приложения или ссылки на App Store — открываем сайт.
        case web(URL)
        case unavailable
    }

    @MainActor
    static func destination(for store: Store, cartDeepLink: URL?) -> Destination {
        if let scheme = store.appScheme,
           let probe = URL(string: "\(scheme)://"),
           UIApplication.shared.canOpenURL(probe) {
            return .app(cartDeepLink ?? probe)
        }
        if let appStore = store.appStoreURL { return .appStore(appStore) }
        if let web = store.webURL { return .web(web) }
        return .unavailable
    }

    /// Текст списка покупок — на случай, если корзину нельзя передать в магазин напрямую.
    static func shoppingList(for quote: CartQuote) -> String {
        quote.lines.map { line in
            let pack = line.offer.packageAmount.rounded() == line.offer.packageAmount
                ? String(Int(line.offer.packageAmount))
                : String(line.offer.packageAmount)
            if line.offer.isWeighted {
                return "• \(line.offer.title ?? line.line.title) — \(Int(line.line.requiredAmount)) \(line.line.unit.short)"
            }
            return "• \(line.offer.title ?? line.line.title) — \(line.packages) × \(pack) \(line.offer.unit.short)"
        }
        .joined(separator: "\n")
    }
}
