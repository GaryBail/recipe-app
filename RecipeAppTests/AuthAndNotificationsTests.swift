import XCTest
@testable import RecipeApp

final class AuthAndNotificationsTests: XCTestCase {
    func testDecodeSessionResponse() throws {
        let json = """
        {"token": "abc", "created": true,
         "user": {"id": "u1", "email": "a@b.ru", "display_name": "Алиса", "city_id": "msk",
                  "has_apple": false, "has_password": true, "created_at": "2026-10-27T10:00:00+00:00"}}
        """
        let response = try APIClient.decoder.decode(SessionResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.token, "abc")
        XCTAssertEqual(response.user.displayName, "Алиса")
        XCTAssertEqual(response.user.cityId, "msk")
        XCTAssertTrue(response.user.hasPassword)
    }

    func testRegisterBodyIsSnakeCase() throws {
        let body = AuthSession.RegisterBody(email: "a@b.ru", password: "secret123", displayName: "А", cityId: nil)
        let json = String(decoding: try APIClient.encoder.encode(body), as: UTF8.self)
        XCTAssertTrue(json.contains("\"display_name\""))
    }

    func testServerErrorMessages() {
        let text = Data(#"{"detail": "Этот email уже зарегистрирован"}"#.utf8)
        XCTAssertEqual(APIClient.errorMessage(from: text), "Этот email уже зарегистрирован")

        let validation = Data(#"{"detail": [{"msg": "Value error, Пароль должен содержать буквы и цифры", "loc": ["body"]}]}"#.utf8)
        XCTAssertEqual(APIClient.errorMessage(from: validation), "Пароль должен содержать буквы и цифры")

        XCTAssertNil(APIClient.errorMessage(from: Data("not json".utf8)))
    }

    func testDecodeNotifications() throws {
        let json = """
        {"unread_count": 1, "items": [{"id": 7, "kind": "comment", "build_id": "b1", "build_name": "Летний",
          "actor_name": "Боб", "stars": 5, "comment": "Вкусно", "title": "Новый отзыв на «Летний»",
          "body": "Боб: Вкусно", "created_at": "2026-10-27T10:00:00+00:00", "is_read": false}]}
        """
        let response = try APIClient.decoder.decode(NotificationsResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.unreadCount, 1)
        XCTAssertEqual(response.items.first?.buildId, "b1")
        XCTAssertEqual(response.items.first?.isRead, false)
    }

    func testPushPayloadBuildId() {
        XCTAssertEqual(PushRegistration.buildId(from: ["aps": [:], "build_id": "b42"]), "b42")
        XCTAssertNil(PushRegistration.buildId(from: ["aps": [:]]))
    }

    func testClientNotConfiguredWithoutServer() {
        let key = PriceProviderFactory.serverURLKey
        let old = UserDefaults.standard.string(forKey: key)
        defer { UserDefaults.standard.set(old, forKey: key) }

        UserDefaults.standard.set("", forKey: key)
        XCTAssertNil(APIClient.fromSettings())
        UserDefaults.standard.set("http://192.168.1.10:8000", forKey: key)
        XCTAssertEqual(APIClient.fromSettings()?.baseURL.absoluteString, "http://192.168.1.10:8000")
    }
}
