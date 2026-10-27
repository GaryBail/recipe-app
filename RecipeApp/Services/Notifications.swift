import Foundation
import Observation
import UIKit
import UserNotifications

struct AppNotificationDTO: Codable, Identifiable, Hashable, Sendable {
    /// Уведомление о цене своей сборки (а не об оценке в сообществе).
    var isPrice: Bool { kind == "price_drop" || kind == "reminder" }

    let id: Int
    let kind: String
    let buildId: String
    let buildName: String
    let actorName: String
    let stars: Int?
    let comment: String?
    let title: String
    let body: String
    let createdAt: String
    let isRead: Bool
}

struct NotificationsResponse: Decodable {
    let items: [AppNotificationDTO]
    let unreadCount: Int
}

/// Список уведомлений и счётчик непрочитанных.
@MainActor
@Observable
final class NotificationCenterModel {
    static let shared = NotificationCenterModel()

    private(set) var items: [AppNotificationDTO] = []
    private(set) var unreadCount = 0
    /// Сборка сообщества, которую нужно открыть после нажатия на push.
    var pendingBuildId: String?
    /// Своя сборка (уведомление о цене), которую нужно открыть после нажатия на push.
    var pendingLocalBuildId: String?

    func refresh() async {
        guard AuthSession.shared.isLoggedIn, let api = APIClient.fromSettings() else { return }
        guard let response: NotificationsResponse = try? await api.send("GET", "notifications") else { return }
        items = response.items
        unreadCount = response.unreadCount
        try? await UNUserNotificationCenter.current().setBadgeCount(unreadCount)
    }

    func markAllRead() async {
        guard unreadCount > 0, let api = APIClient.fromSettings() else { return }
        struct Body: Encodable { let ids: [Int]? }
        let _: APIClient.Empty? = try? await api.send("POST", "notifications/read", body: Body(ids: nil))
        await refresh()
    }

    func reset() {
        items = []
        unreadCount = 0
        Task { try? await UNUserNotificationCenter.current().setBadgeCount(0) }
    }
}

/// Регистрация устройства для push (APNs).
enum PushRegistration {
    static let deviceTokenKey = "apnsDeviceToken"

    @MainActor
    static func requestAndRegister() async {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        if granted { UIApplication.shared.registerForRemoteNotifications() }
    }

    /// Вызывается из AppDelegate, когда Apple выдала токен устройства.
    static func didReceive(deviceToken: Data) async {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(hex, forKey: deviceTokenKey)
        guard let api = APIClient.fromSettings(), api.token != nil else { return }
        struct Body: Encodable { let token: String }
        let _: APIClient.Empty? = try? await api.send("POST", "devices", body: Body(token: hex))
    }

    static func unregister(api: APIClient) async {
        guard let hex = UserDefaults.standard.string(forKey: deviceTokenKey) else { return }
        let _: APIClient.Empty? = try? await api.send("DELETE", "devices/\(hex)")
    }

    /// id сборки из данных push.
    static func buildId(from userInfo: [AnyHashable: Any]) -> String? {
        userInfo["build_id"] as? String
    }

    /// id своей сборки из push о цене.
    static func localBuildId(from userInfo: [AnyHashable: Any]) -> String? {
        userInfo["local_build_id"] as? String
    }

    static func isAuthorized() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .authorized
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { await PushRegistration.didReceive(deviceToken: deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Нормально для симулятора и сборок без платного аккаунта разработчика.
        print("Push registration failed: \(error.localizedDescription)")
    }

    // Push пришёл, когда приложение открыто: показываем баннер и обновляем список.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        Task { @MainActor in await NotificationCenterModel.shared.refresh() }
        completionHandler([.banner, .sound, .badge])
    }

    // Нажатие на push — открываем сборку.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let buildId = PushRegistration.buildId(from: info)
        let localBuildId = PushRegistration.localBuildId(from: info)
        Task { @MainActor in
            if let localBuildId {
                NotificationCenterModel.shared.pendingLocalBuildId = localBuildId
            } else {
                NotificationCenterModel.shared.pendingBuildId = buildId
            }
            await NotificationCenterModel.shared.refresh()
        }
        completionHandler()
    }
}
