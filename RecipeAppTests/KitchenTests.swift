import SwiftData
import XCTest
@testable import RecipeApp

@MainActor
final class KitchenTests: XCTestCase {
    /// Контейнер держим до конца теста: если его освободить, контекст падает при первой записи.
    private var keep: ModelContainer?

    private func container() throws -> ModelContainer {
        let container = try ModelContainer(for: Recipe.self, Ingredient.self, Product.self, Build.self, BuildItem.self,
                                           ShoppingItem.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        keep = container
        return container
    }

    /// Рецепт с ингредиентами (категория, количество, единица).
    private func recipe(_ id: String, servings: Int = 2, minutes: Int = 20,
                        _ items: [(String, String, Double, MeasureUnit)], in context: ModelContext) -> Recipe {
        let recipe = Recipe(id: id, title: id, summary: "", servings: servings, steps: [])
        recipe.cookMinutes = minutes
        context.insert(recipe)
        for (i, item) in items.enumerated() {
            let ingredient = Ingredient(id: "\(id)-\(i)", title: item.0, categoryId: item.1, amount: item.2,
                                        unit: item.3, position: i)
            ingredient.recipe = recipe
            context.insert(ingredient)
        }
        return recipe
    }

    // MARK: Пересчёт порций и формат количества

    func testScalingAndFormatting() throws {
        let context = try container().mainContext
        let r = recipe("soup", servings: 4, [("Картофель", "potato", 300, .grams), ("Яйца", "eggs", 3, .pieces),
                                            ("Молоко", "milk", 750, .milliliters)], in: context)
        let potato = r.sortedIngredients[0], eggs = r.sortedIngredients[1], milk = r.sortedIngredients[2]
        XCTAssertEqual(potato.scaledAmount(servings: 8), 600)
        XCTAssertEqual(potato.amountText(servings: 2), "150 г")
        XCTAssertEqual(eggs.amountText(servings: 2), "1,5 шт")
        XCTAssertEqual(eggs.amountText(servings: 1), "1 шт")       // 0,75 → ближайшая половинка
        XCTAssertEqual(milk.amountText(servings: 8), "1,5 л")
        XCTAssertEqual(MeasureUnit.grams.format(1250), "1,25 кг")
        XCTAssertEqual(MeasureUnit.grams.format(2.5), "2,5 г")
    }

    func testBuildCartLinesFollowServings() throws {
        let context = try container().mainContext
        let r = recipe("pasta", servings: 2, [("Спагетти", "spaghetti", 200, .grams)], in: context)
        let product = Product(id: "barilla", name: "Спагетти", brand: nil, categoryId: "spaghetti", barcode: nil)
        context.insert(product)
        let build = Build(name: "Моя", recipe: r)
        context.insert(build)
        let item = BuildItem(ingredientId: r.sortedIngredients[0].id, product: product)
        item.build = build
        context.insert(item)
        XCTAssertEqual(build.cartLines().first?.requiredAmount, 200)
        build.servings = 5
        XCTAssertEqual(build.cartLines().first?.requiredAmount, 500)
        XCTAssertEqual(ShoppingList.entries(for: build).first?.amount, 500)
    }

    // MARK: Таймеры из текста шагов

    func testStepTimerParsing() {
        XCTAssertEqual(StepTimer.duration(in: "Варите 20 минут, помешивая."), 1200)
        XCTAssertEqual(StepTimer.duration(in: "Обжарьте по 3–4 минуты с каждой стороны."), 240)
        XCTAssertEqual(StepTimer.duration(in: "Тушите под крышкой 1–1,5 часа до мягкости мяса."), 5400)
        XCTAssertEqual(StepTimer.duration(in: "Варите 1,5 часа, затем ещё 10 минут."), 5400)
        XCTAssertEqual(StepTimer.duration(in: "Выпекайте 40 мин при 180 °C."), 2400)
        XCTAssertNil(StepTimer.duration(in: "Нарежьте лук и морковь, посолите."))
        XCTAssertNil(StepTimer.duration(in: "Влейте 200 мл молока."))
        XCTAssertEqual(StepTimer.format(5400), "1:30:00")
        XCTAssertEqual(StepTimer.format(90), "1:30")
    }

    // MARK: Аллергии, ограничения, фильтры

    func testDietWarningsAndFilters() throws {
        let context = try container().mainContext
        let syrniki = recipe("syrniki", [("Творог", "tvorog", 400, .grams), ("Мука", "flour", 60, .grams),
                                        ("Яйца", "eggs", 1, .pieces)], in: context)
        let salad = recipe("salad", minutes: 10, [("Капуста", "cabbage", 500, .grams),
                                                  ("Подсолнечное масло", "sunflower-oil", 30, .milliliters)],
                           in: context)
        let plov = recipe("plov", minutes: 90, [("Свинина", "pork", 500, .grams), ("Рис", "rice", 400, .grams)],
                          in: context)

        let profile = DietProfile(allergens: [.milk, .gluten], vegetarian: true)
        XCTAssertEqual(profile.warnings(for: syrniki), ["молочное: Творог", "глютен: Мука"])
        XCTAssertTrue(profile.fits(salad))
        XCTAssertTrue(profile.warnings(for: plov).contains("мясо или рыба: Свинина"))
        XCTAssertEqual(DietProfile(stored: DietProfile.store([.eggs, .milk]), vegetarian: false).allergens, [.eggs, .milk])

        XCTAssertTrue(RecipeTraits.isLenten(salad))
        XCTAssertFalse(RecipeTraits.isLenten(syrniki))
        XCTAssertTrue(RecipeTraits.isVegetarian(syrniki))
        XCTAssertFalse(RecipeTraits.isVegetarian(plov))
        XCTAssertTrue(RecipeFilter.quick.matches(salad, kcalPerServing: 100, profile: profile))
        XCTAssertFalse(RecipeFilter.quick.matches(plov, kcalPerServing: 600, profile: profile))
        XCTAssertFalse(RecipeFilter.light.matches(plov, kcalPerServing: 600, profile: profile))
        XCTAssertFalse(RecipeFilter.safe.matches(syrniki, kcalPerServing: nil, profile: profile))
    }

    func testDailyNormPercent() {
        let p = DailyNorm.standard.percent(Nutrition(kcal: 500, protein: 37.5, fat: 33.3, carbs: 137.5))
        XCTAssertEqual(p.kcal, 25)
        XCTAssertEqual(p.protein, 50)
        XCTAssertEqual(p.fat, 50)
        XCTAssertEqual(p.carbs, 50)
    }

    // MARK: «Из того, что есть»

    func testFridgeMatching() throws {
        let context = try container().mainContext
        let omelet = recipe("omelet", [("Яйца", "eggs", 3, .pieces), ("Молоко", "milk", 90, .milliliters),
                                      ("Масло", "sunflower-oil", 10, .milliliters)], in: context)
        let pancakes = recipe("pancakes", [("Яйца", "eggs", 2, .pieces), ("Молоко", "milk", 500, .milliliters),
                                          ("Мука", "flour", 200, .grams), ("Сахар", "sugar", 30, .grams)], in: context)
        _ = recipe("borscht", [("Говядина", "beef", 600, .grams), ("Свёкла", "beetroot", 300, .grams),
                               ("Капуста", "cabbage", 300, .grams), ("Картофель", "potato", 300, .grams)], in: context)

        let results = FridgeMatcher.match(recipes: [omelet, pancakes], available: ["eggs", "milk"])
        XCTAssertEqual(results.map(\.recipe.id), ["omelet", "pancakes"])
        XCTAssertTrue(results[0].isComplete)                       // масло считается «всегда есть»
        XCTAssertEqual(results[1].missing.map(\.title), ["Мука"])  // сахар тоже

        let strict = FridgeMatcher.match(recipes: [omelet], available: ["eggs", "milk"], assumeStaples: false)
        XCTAssertEqual(strict.first?.missing.map(\.title), ["Масло"])

        // только «то, что всегда есть» — не повод предлагать рецепт
        XCTAssertTrue(FridgeMatcher.match(recipes: [omelet], available: []).isEmpty)
    }

    // MARK: Список покупок

    func testShoppingListMergesSameProducts() throws {
        let context = try container().mainContext
        let a = [ShoppingEntry(title: "Картофель", categoryId: "potato", productId: nil, amount: 300, unit: .grams, source: "Борщ"),
                 ShoppingEntry(title: "Яйца С0", categoryId: "eggs", productId: "eggs-c0", amount: 2, unit: .pieces, source: "Блины")]
        ShoppingList.add(a, to: [], context: context)
        var items = try context.fetch(FetchDescriptor<ShoppingItem>())
        XCTAssertEqual(items.count, 2)

        let b = [ShoppingEntry(title: "Картофель", categoryId: "potato", productId: nil, amount: 400, unit: .grams, source: "Пюре"),
                 ShoppingEntry(title: "Яйца С1", categoryId: "eggs", productId: "eggs-c1", amount: 1, unit: .pieces, source: "Омлет")]
        ShoppingList.add(b, to: items, context: context)
        items = try context.fetch(FetchDescriptor<ShoppingItem>())
        XCTAssertEqual(items.count, 3)  // разные марки яиц — разные строки
        let potato = try XCTUnwrap(items.first { $0.categoryId == "potato" })
        XCTAssertEqual(potato.amount, 700)
        XCTAssertEqual(potato.sources, ["Борщ", "Пюре"])

        // купленная позиция при повторном добавлении снова нужна — уже на новое количество
        potato.isChecked = true
        ShoppingList.add([b[0]], to: items, context: context)
        XCTAssertFalse(potato.isChecked)
        XCTAssertEqual(potato.amount, 400)

        XCTAssertEqual(ShoppingList.department(for: "potato").title, "Овощи и фрукты")
        XCTAssertTrue(ShoppingList.shareText(items).contains("☐ Картофель — 400 г"))
    }

    // MARK: Передача корзины во ВкусВилл

    func testCartTransferQuantities() {
        let store = Store(id: "vkusvill", name: "ВкусВилл", deliveryFee: 0, freeDeliveryFrom: nil, minOrder: 0,
                          appScheme: nil, appStoreURL: nil, webURL: nil)
        let cheeseLine = CartLine(productId: "p", barcode: nil, title: "Пармезан", requiredAmount: 150, unit: .grams)
        let cheese = StoreOffer(productId: "p", price: 236, packageAmount: 90, unit: .grams, inStock: true, sku: "115018")
        let meatLine = CartLine(productId: "m", barcode: nil, title: "Говядина", requiredAmount: 600, unit: .grams)
        let meat = StoreOffer(productId: "m", price: 900, packageAmount: 1000, unit: .grams, inStock: true,
                              isWeighted: true, sku: "777")
        let quote = CartComparator.quote(lines: [cheeseLine, meatLine], store: store,
                                         offers: ["p": cheese, "m": meat])
        let items = CartTransfer.items(for: quote)
        XCTAssertEqual(items.first { $0.sku == "115018" }?.quantity, 2)    // 2 упаковки по 90 г
        XCTAssertEqual(items.first { $0.sku == "777" }?.quantity, 0.6)     // 0,6 кг весового
    }

    // MARK: Подборки

    func testCollections() throws {
        let context = try container().mainContext
        let quick = recipe("quick", minutes: 15, [("Капуста", "cabbage", 100, .grams)], in: context)
        let slow = recipe("slow", servings: 6, minutes: 120, [("Говядина", "beef", 500, .grams)], in: context)
        XCTAssertEqual(RecipeCollection.quick.recipes(from: [quick, slow]).map(\.id), ["quick"])
        XCTAssertEqual(RecipeCollection.family.recipes(from: [quick, slow]).map(\.id), ["slow"])
        XCTAssertEqual(RecipeCollection.lenten.recipes(from: [quick, slow]).map(\.id), ["quick"])

        let october = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 10, day: 27).date!
        XCTAssertEqual(RecipeCollection.seasonal(for: october).id, "autumn")
        let week = RecipeCollection.all(date: october)[0]
        XCTAssertEqual(week.recipes(from: [quick, slow], popularIds: [], date: october).count, 2)
    }
}
