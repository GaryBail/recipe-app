import Foundation
import Security

/// Токен сессии храним в Keychain, а не в UserDefaults.
enum Keychain {
    private static let service = "com.garybail.recipeapp"

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String?, for key: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}

/// Общий HTTP-клиент нашего сервера: адрес из настроек, токен сессии из Keychain.
struct APIClient: Sendable {
    static let tokenKey = "sessionToken"

    let baseURL: URL
    var token: String?
    var session: URLSession = .shared

    enum APIError: LocalizedError, Equatable {
        case notConfigured
        case unauthorized(String?)
        case status(Int, String?)

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Укажите адрес сервера в настройках."
            case .unauthorized(let detail): return detail ?? "Нужно войти в аккаунт."
            case .status(let code, let detail): return detail ?? "Ошибка сервера (\(code))"
            }
        }
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

    /// nil, если адрес сервера не задан. Адрес выбирает AppConfig (встроенный или из профиля).
    static func fromSettings() -> APIClient? {
        guard let url = AppConfig.serverURL else { return nil }
        return APIClient(baseURL: url, token: Keychain.get(tokenKey))
    }

    struct Empty: Codable {}
    private struct ErrorBody: Decodable {
        let detail: Detail?
        /// FastAPI отдаёт строку или список ошибок валидации.
        enum Detail: Decodable {
            case text(String)
            case validation([Item])
            struct Item: Decodable { let msg: String }
            init(from decoder: Decoder) throws {
                let c = try decoder.singleValueContainer()
                if let s = try? c.decode(String.self) { self = .text(s) }
                else { self = .validation(try c.decode([Item].self)) }
            }
            var message: String {
                switch self {
                case .text(let s): return s
                case .validation(let items):
                    return items.map { $0.msg.replacingOccurrences(of: "Value error, ", with: "") }
                        .joined(separator: "\n")
                }
            }
        }
    }

    static func errorMessage(from data: Data) -> String? {
        (try? JSONDecoder().decode(ErrorBody.self, from: data))?.detail?.message
    }

    /// Загрузка файла: тело запроса — сами байты (например, JPEG).
    func upload<T: Decodable>(_ path: String, data: Data, contentType: String) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (body, response) = try await session.upload(for: request, from: data)
        return try handle(body, response)
    }

    /// Абсолютный адрес файла с сервера («/media/photos/…» → «https://…/media/photos/…»).
    func mediaURL(_ path: String) -> URL? {
        URL(string: path, relativeTo: baseURL)?.absoluteURL
    }

    func send<T: Decodable>(_ method: String, _ path: String, query: [URLQueryItem] = []) async throws -> T {
        try await send(method, path, query: query, body: Optional<Empty>.none)
    }

    func send<T: Decodable, B: Encodable>(_ method: String, _ path: String,
                                          query: [URLQueryItem] = [], body: B?) async throws -> T {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.timeoutInterval = 20
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try Self.encoder.encode(body)
        }

        let (data, response) = try await session.data(for: request)
        return try handle(data, response)
    }

    private func handle<T: Decodable>(_ data: Data, _ response: URLResponse) throws -> T {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300:
            if T.self == Empty.self { return Empty() as! T }
            return try Self.decoder.decode(T.self, from: data)
        case 401:
            throw APIError.unauthorized(Self.errorMessage(from: data))
        default:
            throw APIError.status(status, Self.errorMessage(from: data))
        }
    }
}
