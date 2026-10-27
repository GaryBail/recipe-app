import Foundation
import Observation

struct AccountDTO: Codable, Equatable, Sendable {
    let id: String
    let email: String?
    let displayName: String
    let cityId: String?
    let hasApple: Bool
    let hasPassword: Bool
}

struct SessionResponse: Decodable {
    let token: String
    let user: AccountDTO
    let created: Bool
}

/// Текущий пользователь. Токен — в Keychain, профиль — в памяти (обновляется с сервера).
@MainActor
@Observable
final class AuthSession {
    static let shared = AuthSession()

    private(set) var user: AccountDTO?
    var isLoggedIn: Bool { user != nil }

    /// id пользователя без обращения к MainActor (для сравнения «это моя сборка?»).
    nonisolated static var currentUserId: String? {
        UserDefaults.standard.string(forKey: "currentUserId")
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: "currentUser") {
            user = try? JSONDecoder().decode(AccountDTO.self, from: data)
        }
    }

    private var api: APIClient {
        get throws {
            guard let api = APIClient.fromSettings() else { throw APIClient.APIError.notConfigured }
            return api
        }
    }

    // MARK: - Вход

    struct RegisterBody: Encodable {
        let email: String
        let password: String
        let displayName: String
        let cityId: String?
    }

    func register(email: String, password: String, displayName: String, cityId: String?) async throws {
        let body = RegisterBody(email: email, password: password, displayName: displayName, cityId: cityId)
        let response: SessionResponse = try await api.send("POST", "auth/register", body: body)
        await apply(response)
    }

    func login(email: String, password: String) async throws {
        struct Body: Encodable { let email: String; let password: String }
        let response: SessionResponse = try await api.send("POST", "auth/login",
                                                           body: Body(email: email, password: password))
        await apply(response)
    }

    func signInWithApple(identityToken: String, fullName: PersonNameComponents?) async throws {
        struct Body: Encodable { let identityToken: String; let displayName: String? }
        let name = fullName.map { PersonNameComponentsFormatter.localizedString(from: $0, style: .default) }
        let response: SessionResponse = try await api.send(
            "POST", "auth/apple",
            body: Body(identityToken: identityToken, displayName: (name?.trimmed.isEmpty ?? true) ? nil : name))
        await apply(response)
    }

    // MARK: - Профиль

    /// Проверяет сессию при запуске; если токен отозван — выходим.
    func refresh() async {
        guard Keychain.get(APIClient.tokenKey) != nil, let api = try? self.api else { return }
        do {
            let me: AccountDTO = try await api.send("GET", "auth/me")
            store(me)
        } catch APIClient.APIError.unauthorized {
            clear()
        } catch {
            // нет сети — оставляем сохранённый профиль
        }
    }

    func update(displayName: String? = nil, cityId: String? = nil) async throws {
        struct Body: Encodable { let displayName: String?; let cityId: String? }
        let me: AccountDTO = try await api.send("PATCH", "auth/me",
                                                body: Body(displayName: displayName, cityId: cityId))
        store(me)
    }

    func logout() async {
        if let api = try? self.api {
            await PushRegistration.unregister(api: api)
            let _: APIClient.Empty? = try? await api.send("POST", "auth/logout")
        }
        clear()
    }

    func deleteAccount() async throws {
        let api = try self.api
        await PushRegistration.unregister(api: api)
        let _: APIClient.Empty = try await api.send("DELETE", "auth/me")
        clear()
    }

    // MARK: - Хранение

    private func apply(_ response: SessionResponse) async {
        Keychain.set(response.token, for: APIClient.tokenKey)
        store(response.user)
        await PushRegistration.requestAndRegister()
    }

    private func store(_ account: AccountDTO) {
        user = account
        UserDefaults.standard.set(account.id, forKey: "currentUserId")
        UserDefaults.standard.set(try? JSONEncoder().encode(account), forKey: "currentUser")
    }

    private func clear() {
        Keychain.set(nil, for: APIClient.tokenKey)
        user = nil
        UserDefaults.standard.removeObject(forKey: "currentUserId")
        UserDefaults.standard.removeObject(forKey: "currentUser")
        NotificationCenterModel.shared.reset()
    }
}
