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
                                "-priceServerURL", "", "-uiTesting"]
        app.launch()
    }

    func testWalkThroughScreens() {
        // 1. Главная
        XCTAssertTrue(app.staticTexts["Популярное"].waitForExistence(timeout: 15))
        sleep(1)
        snap("home")
        app.swipeUp()
        snap("home-all")
        app.swipeDown()
        app.swipeDown()

        // 2. Рубрика
        if tapIfExists(app.buttons["Супы"]) {
            sleep(1)
            snap("home-soups")
            tapIfExists(app.buttons["Все"])
        }

        // 3. Поиск и рецепт: фото-заглушка, КБЖУ, ингредиенты
        let search = app.searchFields.firstMatch
        if search.waitForExistence(timeout: 3) {
            search.tap()
            search.typeText("карбонара")
            sleep(1)
            snap("search")
        }
        let carbonara = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Паста карбонара'")).firstMatch
        XCTAssertTrue(carbonara.waitForExistence(timeout: 5))
        carbonara.tap()
        _ = app.navigationBars["Паста карбонара"].waitForExistence(timeout: 5)
        sleep(1)
        snap("recipe")
        if tapIfExists(app.buttons["Поделиться рецептом"]) {
            sleep(2)
            snap("share-sheet")
            if !tapIfExists(app.buttons["Закрыть"], timeout: 2) { tapIfExists(app.buttons["Close"], timeout: 1) }
            sleep(1)
        }
        tapIfExists(app.buttons["В избранное"])
        app.swipeUp()
        snap("recipe-ingredients")

        // 4. Новая сборка
        let collect = app.buttons["Собрать продукты"]
        scrollTo(collect)
        collect.tap()
        XCTAssertTrue(app.navigationBars["Новая сборка"].waitForExistence(timeout: 5))
        choose("carbonara-pasta", "Спагетти №5 · Barilla")
        choose("carbonara-pork", "Гуанчале")
        choose("carbonara-cheese", "Пармезан")
        choose("carbonara-eggs", "Яйца С0")
        choose("carbonara-pepper", "Перец чёрный молотый")
        snap("build-editor")
        app.buttons["Сохранить"].tap()

        // 5. Сборка с КБЖУ
        let build = app.staticTexts["Моя паста карбонара"]
        scrollTo(build)
        if build.exists {
            build.tap()
            XCTAssertTrue(app.buttons["Где купить дешевле"].waitForExistence(timeout: 5))
            snap("build")
            app.swipeUp()
            snap("build-nutrition")
            app.swipeDown()
            app.buttons["Где купить дешевле"].tap()
            _ = app.staticTexts["Магазин А"].waitForExistence(timeout: 8)
            sleep(1)
            snap("compare")
        }
        backToRoot()

        // 6. Избранное
        if tapIfExists(app.tabBars.buttons["Избранное"]) {
            sleep(1)
            snap("favorites")
        }

        // 7. Сообщество
        if tapIfExists(app.tabBars.buttons["Сообщество"]) {
            sleep(1)
            snap("community")
        }

        // 8. Профиль и вход
        if tapIfExists(app.tabBars.buttons["Профиль"]) {
            sleep(1)
            snap("profile")
            if tapIfExists(app.buttons["Войти или зарегистрироваться"]) {
                sleep(1)
                snap("auth-login")
                tapIfExists(app.buttons["Регистрация"])
                sleep(1)
                snap("auth-register")
                tapIfExists(app.buttons["Закрыть"])
                sleep(1)
            }
        }

        // 9. Новый рецепт и уведомления
        tapIfExists(app.tabBars.buttons["Рецепты"])
        if tapIfExists(app.buttons["Новый рецепт"]) {
            _ = app.navigationBars["Новый рецепт"].waitForExistence(timeout: 5)
            snap("new-recipe")
            tapIfExists(app.buttons["Отмена"])
            sleep(1)
        }
        if tapIfExists(app.buttons["Уведомления"]) {
            sleep(1)
            snap("notifications")
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
        }
    }

    private func scrollTo(_ element: XCUIElement, maxSwipes: Int = 8) {
        for _ in 0..<maxSwipes {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
    }

    @discardableResult
    private func tapIfExists(_ element: XCUIElement, timeout: TimeInterval = 3) -> Bool {
        guard element.waitForExistence(timeout: timeout) else { return false }
        element.tap()
        return true
    }

    private func backToRoot() {
        for _ in 0..<5 {
            if app.staticTexts["Популярное"].exists || app.searchFields.firstMatch.isHittable { break }
            let back = app.navigationBars.buttons.element(boundBy: 0)
            guard back.exists else { return }
            back.tap()
            sleep(1)
        }
        // сбросить поиск
        let cancel = app.buttons["Отменить"].exists ? app.buttons["Отменить"] : app.buttons["Cancel"]
        if cancel.exists { cancel.tap() }
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
