package com.garybail.vyborvkusa.core

import kotlin.math.floor

/** Единица измерения количества ингредиента / фасовки товара. Значения raw — как в seed.json и на сервере. */
enum class MeasureUnit(val raw: String, val short: String) {
    GRAMS("g", "г"),
    MILLILITERS("ml", "мл"),
    PIECES("pcs", "шт");

    /** «250 г», «1,5 шт», «1,25 кг» — без лишних нулей. Штуки округляем до половинок. */
    fun format(amount: Double): String = when (this) {
        PIECES -> "${number(maxOf(0.5, roundHalfUp(amount * 2) / 2))} шт"
        GRAMS -> if (amount >= 1000) "${number(roundHalfUp(amount / 10) / 100)} кг" else "${number(small(amount))} г"
        MILLILITERS -> if (amount >= 1000) "${number(roundHalfUp(amount / 10) / 100)} л" else "${number(small(amount))} мл"
    }

    companion object {
        fun fromRaw(raw: String?): MeasureUnit = entries.firstOrNull { it.raw == raw } ?: PIECES

        private fun small(x: Double) = if (x >= 10) roundHalfUp(x) else roundHalfUp(x * 10) / 10

        /** Число по-русски: «2», «1,5», «1,25». */
        fun number(x: Double): String {
            if (roundHalfUp(x) == x) return x.toLong().toString()
            val text = String.format(java.util.Locale.US, "%.2f", x).trimEnd('0').trimEnd('.')
            return text.replace('.', ',')
        }
    }
}

/** Округление «половина вверх», как .rounded() в Swift (для положительных чисел). */
fun roundHalfUp(x: Double): Double = if (x >= 0) floor(x + 0.5) else -floor(-x + 0.5)

/** Ингредиент рецепта — это категория («Твёрдый сыр»), а не конкретный товар. */
data class Ingredient(
    val id: String,
    val title: String,
    val categoryId: String,
    val amount: Double,
    val unit: MeasureUnit,
    val position: Int,
)

/** Рецепт из каталога. */
data class Recipe(
    val id: String,
    val title: String,
    val summary: String,
    val servings: Int,
    val steps: List<String>,
    val ingredients: List<Ingredient>,
    /** Рубрика: breakfast, soup, salad, main, side, pastry, sauce. */
    val rubric: String = "",
    /** Кухня: russian, italian… (пусто — без кухни). */
    val cuisine: String = "",
    val cookMinutes: Int = 0,
    /** Иллюстрация: assets/Food/food-<icon>.png. */
    val icon: String = "",
    val featured: Boolean = false,
    val isUserCreated: Boolean = false,
) {
    /** Количество ингредиента с учётом выбранного числа порций. */
    fun scaledAmount(ingredient: Ingredient, servings: Int): Double =
        if (this.servings <= 0 || servings <= 0) ingredient.amount
        else ingredient.amount * servings / this.servings

    fun amountText(ingredient: Ingredient, servings: Int): String =
        ingredient.unit.format(scaledAmount(ingredient, servings))
}

/** КБЖУ на 100 г. */
data class Nutrition(
    val kcal: Double = 0.0,
    val protein: Double = 0.0,
    val fat: Double = 0.0,
    val carbs: Double = 0.0,
) {
    operator fun plus(o: Nutrition) = Nutrition(kcal + o.kcal, protein + o.protein, fat + o.fat, carbs + o.carbs)
    fun scaled(k: Double) = Nutrition(kcal * k, protein * k, fat * k, carbs * k)

    /** «323 ккал · Б 23 · Ж 17 · У 20» */
    val shortText: String
        get() = "${roundHalfUp(kcal).toInt()} ккал · Б ${roundHalfUp(protein).toInt()} · " +
            "Ж ${roundHalfUp(fat).toInt()} · У ${roundHalfUp(carbs).toInt()}"

    companion object {
        val ZERO = Nutrition()
    }
}

/** Конкретный продукт каталога («Пармезан · Galbani»). */
data class Product(
    val id: String,
    val name: String,
    val brand: String?,
    val categoryId: String,
    val barcode: String? = null,
    val nutrition: Nutrition? = null,
    /** Вес одной штуки, г (для ингредиентов в штуках). */
    val gramsPerPiece: Double? = null,
    /** Плотность, г/мл (для жидкостей). */
    val density: Double? = null,
) {
    val displayName: String get() = if (!brand.isNullOrEmpty()) "$name · $brand" else name
}

/** Категория продуктов: название, отдел магазина, аллергены, признаки (meat, fish, animal, staple). */
data class CategoryInfo(
    val id: String,
    val title: String,
    val department: Int?,
    val allergens: List<String>,
    val tags: List<String>,
)

data class Rubric(val id: String, val title: String, val icon: String?)

data class Cuisine(val id: String, val title: String, val icon: String)
