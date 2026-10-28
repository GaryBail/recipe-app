package com.garybail.vyborvkusa.core

// ---------- КБЖУ ----------

/** Строка для расчёта: сколько чего и какой продукт. */
data class NutritionLine(val title: String, val amount: Double, val unit: MeasureUnit, val product: Product?)

data class NutritionSummary(
    val total: Nutrition,
    /** Вес всех продуктов с известным КБЖУ, г (по сырым продуктам). */
    val grams: Double,
    /** Ингредиенты, для которых посчитать не удалось. */
    val missing: List<String>,
) {
    fun perServing(servings: Int): Nutrition = total.scaled(1.0 / maxOf(servings, 1))
    val per100g: Nutrition? get() = if (grams > 0) total.scaled(100 / grams) else null
}

object NutritionCalculator {
    /** Количество в граммах: граммы как есть, миллилитры через плотность, штуки через вес штуки. */
    fun grams(amount: Double, unit: MeasureUnit, product: Product): Double? = when (unit) {
        MeasureUnit.GRAMS -> amount
        MeasureUnit.MILLILITERS -> amount * (product.density ?: 1.0)
        MeasureUnit.PIECES -> product.gramsPerPiece?.let { amount * it }
    }

    fun summary(lines: List<NutritionLine>): NutritionSummary {
        var total = Nutrition.ZERO
        var grams = 0.0
        val missing = mutableListOf<String>()
        for (line in lines) {
            val product = line.product
            val n = product?.nutrition
            val g = product?.let { grams(line.amount, line.unit, it) }
            if (n == null || g == null) {
                missing += line.title
                continue
            }
            total += n.scaled(g / 100)
            grams += g
        }
        return NutritionSummary(total, grams, missing)
    }
}

/** Типичный продукт каждой категории (первый по названию с КБЖУ) — для КБЖУ рецепта до выбора продуктов. */
class NutritionIndex(products: List<Product>) {
    val typical: Map<String, Product> = products.filter { it.nutrition != null }
        .groupBy { it.categoryId }
        .mapValues { (_, list) -> list.minWith(compareBy(RU_COLLATOR) { it.name }) }

    fun summary(recipe: Recipe): NutritionSummary = NutritionCalculator.summary(
        recipe.ingredients.map { NutritionLine(it.title, it.amount, it.unit, typical[it.categoryId]) })

    /** Калорийность порции; null — посчитать не удалось. */
    fun kcalPerServing(recipe: Recipe): Double? {
        val s = summary(recipe)
        return if (s.grams > 0) s.perServing(recipe.servings).kcal else null
    }
}

/** Сравнение строк по-русски (ё рядом с е, регистр не важен). */
val RU_COLLATOR: java.text.Collator = java.text.Collator.getInstance(java.util.Locale("ru", "RU"))

/** Дневная норма для процентов КБЖУ. Доли энергии: белки 15 %, жиры 30 %, углеводы 55 %. */
data class DailyNorm(val kcal: Double) {
    val protein get() = kcal * 0.15 / 4
    val fat get() = kcal * 0.30 / 9
    val carbs get() = kcal * 0.55 / 4

    data class Percent(val kcal: Int, val protein: Int, val fat: Int, val carbs: Int)

    fun percent(n: Nutrition): Percent {
        fun p(v: Double, norm: Double) = if (norm > 0) roundHalfUp(v / norm * 100).toInt() else 0
        return Percent(p(n.kcal, kcal), p(n.protein, protein), p(n.fat, fat), p(n.carbs, carbs))
    }

    companion object {
        val STANDARD = DailyNorm(2000.0)
    }
}

// ---------- Аллергены и ограничения ----------

enum class Allergen(val raw: String, val title: String, val short: String) {
    MILK("milk", "Молоко и молочное", "молочное"),
    EGGS("eggs", "Яйца", "яйца"),
    GLUTEN("gluten", "Глютен (пшеница, рожь, ячмень)", "глютен"),
    FISH("fish", "Рыба", "рыба"),
    SEAFOOD("seafood", "Морепродукты", "морепродукты"),
    NUTS("nuts", "Орехи", "орехи"),
    PORK("pork", "Свинина", "свинина");

    companion object {
        fun fromRaw(raw: String) = entries.firstOrNull { it.raw == raw }
    }
}

/** Свойства рецептов для фильтров и подборок. Определяются по категориям ингредиентов каталога. */
class RecipeTraits(private val catalog: Catalog) {
    private val meat = catalog.categoriesTagged("meat")
    private val fish = catalog.categoriesTagged("fish")
    private val animal = catalog.categoriesTagged("animal")
    val meatOrFish: Set<String> = meat + fish

    private fun categories(recipe: Recipe) = recipe.ingredients.mapTo(HashSet()) { it.categoryId }

    /** Без мяса и рыбы. */
    fun isVegetarian(recipe: Recipe) = categories(recipe).none { it in meatOrFish }

    /** Постное: без мяса, рыбы, молочного и яиц. */
    fun isLenten(recipe: Recipe) = categories(recipe).none { it in meatOrFish || it in animal }

    fun isQuick(recipe: Recipe) = recipe.cookMinutes in 1..30

    fun allergens(recipe: Recipe): List<Pair<Allergen, List<String>>> = Allergen.entries.mapNotNull { allergen ->
        val cats = catalog.categoriesWithAllergen(allergen.raw)
        val titles = recipe.ingredients.filter { it.categoryId in cats }.map { it.title }
        if (titles.isEmpty()) null else allergen to titles
    }
}

/** Ограничения пользователя (из профиля). */
data class DietProfile(val allergens: Set<Allergen> = emptySet(), val vegetarian: Boolean = false) {
    val isEmpty get() = allergens.isEmpty() && !vegetarian

    /** Предупреждения для рецепта: «молочное: Сметана, Сливочное масло». */
    fun warnings(recipe: Recipe, traits: RecipeTraits): List<String> {
        val result = traits.allergens(recipe).filter { it.first in allergens }
            .map { "${it.first.short}: ${it.second.joinToString(", ")}" }.toMutableList()
        if (vegetarian && !traits.isVegetarian(recipe)) {
            val meat = recipe.ingredients.filter { it.categoryId in traits.meatOrFish }.map { it.title }
            result += "мясо или рыба: ${meat.joinToString(", ")}"
        }
        return result
    }

    fun fits(recipe: Recipe, traits: RecipeTraits) = warnings(recipe, traits).isEmpty()

    companion object {
        /** Из строки настроек «milk,eggs». */
        fun stored(text: String, vegetarian: Boolean) =
            DietProfile(text.split(",").mapNotNull { Allergen.fromRaw(it.trim()) }.toSet(), vegetarian)

        fun store(allergens: Set<Allergen>) = allergens.map { it.raw }.sorted().joinToString(",")
    }
}

/** Фильтры каталога на главной. */
enum class RecipeFilter(val title: String) {
    QUICK("До 30 минут"),
    VEGETARIAN("Без мяса"),
    LENTEN("Постное"),
    LIGHT("Лёгкое"),
    SAFE("Мне подходит");

    fun matches(recipe: Recipe, kcalPerServing: Double?, profile: DietProfile, traits: RecipeTraits): Boolean =
        when (this) {
            QUICK -> traits.isQuick(recipe)
            VEGETARIAN -> traits.isVegetarian(recipe)
            LENTEN -> traits.isLenten(recipe)
            LIGHT -> (kcalPerServing ?: Double.POSITIVE_INFINITY) <= 350
            SAFE -> profile.fits(recipe, traits)
        }
}
