package com.garybail.vyborvkusa.core

import java.io.File
import java.math.BigDecimal
import java.time.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlinx.coroutines.test.runTest

/** Те же случаи, что в iOS-тестах (KitchenTests, CartComparatorTests): обе платформы считают одинаково. */
class CoreTests {
    private val catalog: Catalog by lazy { Catalog.parse(File(System.getProperty("seedPath")).readText()) }
    private val traits by lazy { RecipeTraits(catalog) }

    private fun recipe(
        id: String, servings: Int = 2, minutes: Int = 20,
        vararg items: Triple<String, String, Pair<Double, MeasureUnit>>,
    ) = Recipe(id, id, "", servings, emptyList(),
               items.mapIndexed { i, (title, cat, amount) -> Ingredient("$id-$i", title, cat, amount.first, amount.second, i) },
               cookMinutes = minutes)

    private fun ing(title: String, cat: String, amount: Double, unit: MeasureUnit) = Triple(title, cat, amount to unit)

    private val g = MeasureUnit.GRAMS
    private val ml = MeasureUnit.MILLILITERS
    private val pcs = MeasureUnit.PIECES

    // --- Каталог ---

    @Test
    fun seedDecodes() {
        assertEquals(337, catalog.recipes.size)
        assertTrue(catalog.products.all { it.nutrition != null }, "у всех продуктов есть КБЖУ")
        val categories = catalog.products.map { it.categoryId }.toSet()
        for (r in catalog.recipes) for (i in r.ingredients) {
            assertTrue(i.categoryId in categories, "Нет продуктов для категории ${i.categoryId}")
        }
        assertEquals("Овощи и фрукты", catalog.department("potato").second)
        assertEquals("Консервы, масла, соусы", catalog.department("fish-sauce").second)
        assertEquals("Другое", catalog.department("user-cat-123").second)
        assertTrue("lamb" in catalog.categoriesTagged("meat"))
        assertTrue("soy-sauce" in catalog.categoriesWithAllergen("gluten"))
        assertEquals("Сыр твёрдый", catalog.category("hard-cheese")?.title)
        assertEquals("Японская", catalog.cuisine("japanese")?.title)
        assertTrue(catalog.rubrics.any { it.id == "sauce" })
    }

    @Test
    fun nutritionIndexPicksFirstProductByName() {
        fun p(id: String, name: String, n: Boolean = true) =
            Product(id, name, null, "cheese", nutrition = if (n) Nutrition(100.0) else null)
        val index = NutritionIndex(listOf(p("b", "Пармезан"), p("a", "Грана Падано"), p("c", "Аааа без КБЖУ", false)))
        assertEquals("a", index.typical["cheese"]?.id)
        val carbonara = catalog.recipe("carbonara")!!
        val kcal = NutritionIndex(catalog.products).kcalPerServing(carbonara)
        assertNotNull(kcal)
        assertTrue(kcal > 300, "карбонара сытная: $kcal")
    }

    // --- Порции и формат ---

    @Test
    fun scalingAndFormatting() {
        val r = recipe("soup", 4, 20, ing("Картофель", "potato", 300.0, g), ing("Яйца", "eggs", 3.0, pcs),
                       ing("Молоко", "milk", 750.0, ml))
        val (potato, eggs, milk) = r.ingredients
        assertEquals(600.0, r.scaledAmount(potato, 8))
        assertEquals("150 г", r.amountText(potato, 2))
        assertEquals("1,5 шт", r.amountText(eggs, 2))
        assertEquals("1 шт", r.amountText(eggs, 1))
        assertEquals("1,5 л", r.amountText(milk, 8))
        assertEquals("1,25 кг", g.format(1250.0))
        assertEquals("2,5 г", g.format(2.5))
    }

    @Test
    fun buildCartLinesFollowServings() {
        val carbonara = catalog.recipe("carbonara")!!
        val pasta = carbonara.ingredients.first()
        val product = catalog.productsByCategory.getValue(pasta.categoryId).first()
        var build = Build("b1", "Моя", carbonara.id, mapOf(pasta.id to product.id), 0)
        assertEquals(200.0, build.cartLines(catalog).first().requiredAmount)
        build = build.copy(servings = 5)
        assertEquals(500.0, build.cartLines(catalog).first().requiredAmount)
        assertEquals(500.0, ShoppingList.entries(build, catalog).first().amount)
    }

    // --- Таймеры ---

    @Test
    fun stepTimerParsing() {
        assertEquals(1200L, StepTimer.duration("Варите 20 минут, помешивая."))
        assertEquals(240L, StepTimer.duration("Обжарьте по 3–4 минуты с каждой стороны."))
        assertEquals(5400L, StepTimer.duration("Тушите под крышкой 1–1,5 часа до мягкости мяса."))
        assertEquals(5400L, StepTimer.duration("Варите 1,5 часа, затем ещё 10 минут."))
        assertEquals(2400L, StepTimer.duration("Выпекайте 40 мин при 180 °C."))
        assertNull(StepTimer.duration("Нарежьте лук и морковь, посолите."))
        assertNull(StepTimer.duration("Влейте 200 мл молока."))
        assertEquals("1:30:00", StepTimer.format(5400))
        assertEquals("1:30", StepTimer.format(90))
    }

    // --- Диета и фильтры ---

    @Test
    fun dietWarningsAndFilters() {
        val syrniki = recipe("syrniki", 2, 20, ing("Творог", "tvorog", 400.0, g), ing("Мука", "flour", 60.0, g),
                             ing("Яйца", "eggs", 1.0, pcs))
        val salad = recipe("salad", 2, 10, ing("Капуста", "cabbage", 500.0, g),
                           ing("Подсолнечное масло", "sunflower-oil", 30.0, ml))
        val plov = recipe("plov", 2, 90, ing("Свинина", "pork", 500.0, g), ing("Рис", "rice", 400.0, g))

        val profile = DietProfile(setOf(Allergen.MILK, Allergen.GLUTEN), vegetarian = true)
        assertEquals(listOf("молочное: Творог", "глютен: Мука"), profile.warnings(syrniki, traits))
        assertTrue(profile.fits(salad, traits))
        assertTrue("мясо или рыба: Свинина" in profile.warnings(plov, traits))
        assertEquals(setOf(Allergen.EGGS, Allergen.MILK),
                     DietProfile.stored(DietProfile.store(setOf(Allergen.EGGS, Allergen.MILK)), false).allergens)

        assertTrue(traits.isLenten(salad))
        assertFalse(traits.isLenten(syrniki))
        assertTrue(traits.isVegetarian(syrniki))
        assertFalse(traits.isVegetarian(plov))
        assertTrue(RecipeFilter.QUICK.matches(salad, 100.0, profile, traits))
        assertFalse(RecipeFilter.QUICK.matches(plov, 600.0, profile, traits))
        assertFalse(RecipeFilter.LIGHT.matches(plov, 600.0, profile, traits))
        assertFalse(RecipeFilter.SAFE.matches(syrniki, null, profile, traits))
    }

    @Test
    fun dailyNormPercent() {
        val p = DailyNorm.STANDARD.percent(Nutrition(500.0, 37.5, 33.3, 137.5))
        assertEquals(DailyNorm.Percent(25, 50, 50, 50), p)
    }

    // --- «Из того, что есть» ---

    @Test
    fun fridgeMatching() {
        val fridge = FridgeMatcher(catalog)
        val omelet = recipe("omelet", 2, 20, ing("Яйца", "eggs", 3.0, pcs), ing("Молоко", "milk", 90.0, ml),
                            ing("Масло", "sunflower-oil", 10.0, ml))
        val pancakes = recipe("pancakes", 2, 20, ing("Яйца", "eggs", 2.0, pcs), ing("Молоко", "milk", 500.0, ml),
                              ing("Мука", "flour", 200.0, g), ing("Сахар", "sugar", 30.0, g))
        val results = fridge.match(listOf(omelet, pancakes), setOf("eggs", "milk"))
        assertEquals(listOf("omelet", "pancakes"), results.map { it.recipe.id })
        assertTrue(results[0].isComplete)
        assertEquals(listOf("Мука"), results[1].missing.map { it.title })
        val strict = fridge.match(listOf(omelet), setOf("eggs", "milk"), assumeStaples = false)
        assertEquals(listOf("Масло"), strict.first().missing.map { it.title })
        assertTrue(fridge.match(listOf(omelet), emptySet()).isEmpty())
        assertTrue(fridge.categories("курица").isNotEmpty())
    }

    // --- Список покупок ---

    @Test
    fun shoppingListMergesSameProducts() {
        val a = listOf(ShoppingEntry("Картофель", "potato", null, 300.0, g, "Борщ"),
                       ShoppingEntry("Яйца С0", "eggs", "eggs-c0", 2.0, pcs, "Блины"))
        var items = ShoppingList.add(a, emptyList())
        assertEquals(2, items.size)
        val b = listOf(ShoppingEntry("Картофель", "potato", null, 400.0, g, "Пюре"),
                       ShoppingEntry("Яйца С1", "eggs", "eggs-c1", 1.0, pcs, "Омлет"))
        items = ShoppingList.add(b, items)
        assertEquals(3, items.size)  // разные марки яиц — разные строки
        val potato = items.first { it.categoryId == "potato" }
        assertEquals(700.0, potato.amount)
        assertEquals(listOf("Борщ", "Пюре"), potato.sources)

        items = items.map { if (it.id == potato.id) it.copy(isChecked = true) else it }
        items = ShoppingList.add(listOf(b[0]), items)
        val again = items.first { it.id == potato.id }
        assertFalse(again.isChecked)
        assertEquals(400.0, again.amount)
        assertTrue("☐ Картофель — 400 г" in ShoppingList.shareText(items, catalog))
    }

    // --- Корзины ---

    private val cheese = CartLine("parmesan", null, "Пармезан", 100.0, g)
    private val eggs = CartLine("eggs", null, "Яйца", 3.0, pcs)

    private fun store(id: String, fee: Int = 100, freeFrom: Int? = null, minOrder: Int = 0) =
        Store(id, id, BigDecimal(fee), freeFrom?.let { BigDecimal(it) }, BigDecimal(minOrder))

    private fun offer(id: String, price: Int, pack: Double, unit: MeasureUnit, inStock: Boolean = true) =
        StoreOffer(id, BigDecimal(price), pack, unit, inStock)

    @Test
    fun packagesRoundUp() {
        assertEquals(1, CartComparator.packagesNeeded(100.0, g, offer("x", 1, 250.0, g)))
        assertEquals(2, CartComparator.packagesNeeded(400.0, g, offer("x", 1, 250.0, g)))
        assertEquals(1, CartComparator.packagesNeeded(3.0, pcs, offer("x", 1, 10.0, pcs)))
    }

    @Test
    fun quoteTotalsDeliveryAndMinOrder() {
        val quote = CartComparator.quote(listOf(cheese, eggs), store("a", 199, minOrder = 1000),
            mapOf("parmesan" to offer("parmesan", 300, 200.0, g), "eggs" to offer("eggs", 120, 10.0, pcs)))
        assertTrue(quote.isComplete)
        assertEquals(0, BigDecimal(420).compareTo(quote.itemsTotal))
        assertEquals(0, BigDecimal(619).compareTo(quote.total))
        assertEquals(0, BigDecimal(580).compareTo(quote.minOrderShortfall))
        val free = CartComparator.quote(listOf(cheese), store("a", 199, freeFrom = 300),
                                        mapOf("parmesan" to offer("parmesan", 300, 200.0, g)))
        assertEquals(0, BigDecimal.ZERO.compareTo(free.deliveryFee))
        val missing = CartComparator.quote(listOf(cheese, eggs), store("a"),
                                           mapOf("parmesan" to offer("parmesan", 300, 200.0, g, inStock = false)))
        assertEquals(2, missing.missing.size)
    }

    @Test
    fun rankingPrefersCompleteThenCheapest() {
        val offers = mapOf("parmesan" to offer("parmesan", 300, 200.0, g), "eggs" to offer("eggs", 120, 10.0, pcs))
        val expensive = CartComparator.quote(listOf(cheese, eggs), store("exp", 500), offers)
        val cheap = CartComparator.quote(listOf(cheese, eggs), store("cheap", 0), offers)
        val incomplete = CartComparator.quote(listOf(cheese, eggs), store("inc", 0), mapOf("eggs" to offers.getValue("eggs")))
        assertEquals(listOf("cheap", "exp", "inc"), CartComparator.rank(listOf(incomplete, expensive, cheap)).map { it.store.id })
    }

    @Test
    fun cartTransferQuantities() {
        val quote = CartComparator.quote(
            listOf(CartLine("p", null, "Пармезан", 150.0, g), CartLine("m", null, "Говядина", 600.0, g)),
            store("vkusvill"),
            mapOf("p" to StoreOffer("p", BigDecimal(236), 90.0, g, sku = "115018"),
                  "m" to StoreOffer("m", BigDecimal(900), 1000.0, g, isWeighted = true, sku = "777")))
        val items = CartTransfer.items(quote).toMap()
        assertEquals(2.0, items["115018"])
        assertEquals(0.6, items["777"])
        assertEquals(0, BigDecimal("540.00").compareTo(quote.lines.first { it.offer.sku == "777" }.cost))
    }

    @Test
    fun compareWithMockProvider() = runTest {
        val lines = listOf(cheese, eggs)
        val quotes = compareCarts(MockPriceProvider(), lines, City("spb", "Санкт-Петербург"))
        assertEquals(3, quotes.size)
    }

    @Test
    fun decodesServerOffers() {
        val text = """{"offers": {"parmesan": {"offer": {"store_id": "lenta", "sku": "123", "title": "Сыр Пармезан 200г",
            "price": "329.99", "package_amount": 200.0, "unit": "g", "in_stock": true, "is_weighted": false,
            "regular_price": null, "image_url": null}, "cost": "329.99", "relevance": 1.0, "alternatives": []}}}"""
        val offers = RemotePriceProvider("http://x").decodeOffers(text)
        val o = offers.getValue("parmesan")
        assertEquals(0, BigDecimal("329.99").compareTo(o.price))
        assertEquals("123", o.sku)
        assertEquals(200.0, o.packageAmount)
        assertNull(serverUrlOrNull(""))
        assertNull(serverUrlOrNull("not a url"))
        assertEquals("https://api.vyborvkusa.ru", serverUrlOrNull(" https://api.vyborvkusa.ru/ "))
    }

    // --- Подборки и данные пользователя ---

    @Test
    fun collections() {
        val quick = recipe("quick", 2, 15, ing("Капуста", "cabbage", 100.0, g))
        val slow = recipe("slow", 6, 120, ing("Говядина", "beef", 500.0, g))
        assertEquals(listOf("quick"), RecipeCollection.QUICK.recipes(listOf(quick, slow), traits).map { it.id })
        assertEquals(listOf("slow"), RecipeCollection.FAMILY.recipes(listOf(quick, slow), traits).map { it.id })
        assertEquals(listOf("quick"), RecipeCollection.LENTEN.recipes(listOf(quick, slow), traits).map { it.id })
        val october = LocalDate.of(2026, 10, 27)
        assertEquals("autumn", RecipeCollection.seasonal(october).id)
        assertEquals(2, RecipeCollection.all(october)[0].recipes(listOf(quick, slow), traits, date = october).size)
    }

    @Test
    fun userDataRoundTripAndOldFiles() {
        val data = UserData(builds = listOf(Build("b", "Моя", "carbonara", mapOf("x" to "y"), 1L, servings = 3)),
                            favorites = mapOf("carbonara" to 5L))
        assertEquals(data, UserData.decode(data.encode()))
        // файл старой версии без новых полей читается
        val old = UserData.decode("""{"favorites": {"borscht": 1}}""")
        assertTrue(old.isFavorite("borscht"))
        assertEquals("spb", old.settings.cityId)
    }
}
