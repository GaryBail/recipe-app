import Foundation

/// Настройки приложения, которые задаются при сборке (Info.plist ← project.yml).
///
/// - `VVServerURL` — адрес сервера. Для App Store прописывается в сборке, пользователь его не видит.
/// - `VVAllowServerOverride` — можно ли указать свой адрес в профиле (тестовые сборки).
///   В сборке для App Store должно быть `NO`.
enum AppConfig {
    static let overrideKey = PriceProviderFactory.serverURLKey

    /// Адрес сервера, встроенный в сборку (может быть пустым, пока сервер не арендован).
    static var builtInServerURL: URL? { url(from: info("VVServerURL")) }

    /// Показывать ли поле «Сервер» в профиле.
    static var allowsServerOverride: Bool {
        (info("VVAllowServerOverride") ?? "YES").uppercased() != "NO"
    }

    /// Адрес сервера для всех запросов: свой адрес из профиля (если разрешено), иначе встроенный.
    static var serverURL: URL? {
        if allowsServerOverride, let custom = url(from: UserDefaults.standard.string(forKey: overrideKey)) {
            return custom
        }
        return builtInServerURL
    }

    static func url(from raw: String?) -> URL? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$("), let url = URL(string: trimmed),
              url.scheme?.hasPrefix("http") == true, url.host != nil else { return nil }
        return url
    }

    private static func info(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }
}
