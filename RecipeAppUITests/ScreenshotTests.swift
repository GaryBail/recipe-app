import XCTest

/// Проходит по основным экранам как пользователь и сохраняет скриншоты.
/// Папка задаётся переменной SCREENSHOTS_DIR (в CI: TEST_RUNNER_SCREENSHOTS_DIR).
final class ScreenshotTests: XCTestCase {
    private var app: XCUIApplication!
    private var counter = 0

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU",
                                "-priceServerURL", ""]
        app.launch()
    }

    func testWalkThroughScreens() {
        // 1. Список рецептов (стартовые данные грузятся при первом запуске)
        XCTAssertTrue(app.staticTexts["Паста карбонара"].waitForExistence(timeout: 15))
        snap("recipes")

        // 2. Рецепт
        app.staticTexts["Паста карбонара"].tap()
        XCTAssertTrue(app.buttons["Собрать продукты"].waitForExistence(timeout: 5))
        snap("recipe")
        app.swipeUp()
        snap("recipe-bottom")
        app.swipeDown()

        // 3. Новая сборка: выбираем продукт для каждого ингредиента
        app.buttons["Собрать продукты"].tap()
        XCTAssertTrue(app.navigationBars["Новая сборка"].waitForExistence(timeout: 5))
        snap("build-editor-empty")
        choose("carbonara-pasta", "Спагетти №5 · Barilla")
        snapIfMenuOpen("build-editor-menu", ingredient: "carbonara-cheese")
        choose("carbonara-pork", "Гуанчале")
        choose("carbonara-cheese", "Пармезан")
        choose("carbonara-eggs", "Яйца С0")
        choose("carbonara-pepper", "Перец чёрный молотый")
        snap("build-editor-filled")
        app.buttons["Сохранить"].tap()

        // 4. Сборка
        let build = app.staticTexts["Моя паста карбонара"]
        if build.waitForExistence(timeout: 5) {
            build.tap()
            XCTAssertTrue(app.buttons["Где купить дешевле"].waitForExistence(timeout: 5))
            snap("build")
            app.swipeUp()
            snap("build-bottom")
            app.swipeDown()

            // 5. Сравнение магазинов (тестовые цены)
            app.buttons["Где купить дешевле"].tap()
            _ = app.staticTexts["Магазин А"].waitForExistence(timeout: 8)
            sleep(1)
            snap("compare")
        }
        backToRoot()

        // 6. Новый рецепт
        if tapIfExists(app.buttons["Новый рецепт"]) {
            _ = app.navigationBars["Новый рецепт"].waitForExistence(timeout: 5)
            snap("new-recipe")
            tapIfExists(app.buttons["Отмена"])
        }

        // 7. Настройки и вход
        if tapIfExists(app.buttons["Настройки"]) {
            _ = app.navigationBars["Настройки"].waitForExistence(timeout: 5)
            snap("settings")
            if tapIfExists(app.buttons["Войти или зарегистрироваться"]) {
                sleep(1)
                snap("auth-login")
                tapIfExists(app.buttons["Регистрация"])
                sleep(1)
                snap("auth-register")
                tapIfExists(app.buttons["Закрыть"])
                sleep(1)
            }
            tapIfExists(app.buttons["Готово"])
            sleep(1)
        }

        // 8. Сообщество и уведомления
        if tapIfExists(app.buttons["Сообщество"]) {
            sleep(1)
            snap("community")
            backToRoot()
        }
        if tapIfExists(app.buttons["Уведомления"]) {
            sleep(1)
            snap("notifications")
            backToRoot()
        }
    }

    // MARK: - Помощники

    private func choose(_ ingredientId: String, _ product: String) {
        let picker = app.buttons["picker-\(ingredientId)"]
        guard picker.waitForExistence(timeout: 3) else {
            XCTFail("Нет выбора для \(ingredientId)")
            return
        }
        picker.tap()
        let option = app.buttons[product]
        if option.waitForExistence(timeout: 3) {
            option.tap()
        } else {
            XCTFail("Нет варианта «\(product)»")
            app.tap()
        }
    }

    /// Снимок раскрытого меню выбора продукта — чтобы было видно, как выглядит выбор.
    private func snapIfMenuOpen(_ name: String, ingredient: String) {
        let picker = app.buttons["picker-\(ingredient)"]
        guard picker.waitForExistence(timeout: 3) else { return }
        picker.tap()
        sleep(1)
        snap(name)
        // закрываем меню, ничего не выбрав
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).tap()
        sleep(1)
    }

    @discardableResult
    private func tapIfExists(_ element: XCUIElement, timeout: TimeInterval = 3) -> Bool {
        guard element.waitForExistence(timeout: timeout) else { return false }
        element.tap()
        return true
    }

    private func backToRoot() {
        for _ in 0..<4 {
            let back = app.navigationBars.buttons.element(boundBy: 0)
            if app.staticTexts["Паста карбонара"].exists && app.navigationBars["Рецепты"].exists { return }
            guard back.exists else { return }
            back.tap()
            sleep(1)
        }
    }

    private func snap(_ name: String) {
        counter += 1
        let fileName = String(format: "%02d-%@", counter, name)
        let shot = XCUIScreen.main.screenshot()

        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = fileName
        attachment.lifetime = .keepAlways
        add(attachment)

        if let dir = ProcessInfo.processInfo.environment["SCREENSHOTS_DIR"], !dir.isEmpty {
            let url = URL(fileURLWithPath: dir).appendingPathComponent("\(fileName).png")
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try? shot.pngRepresentation.write(to: url)
        }
    }
}
