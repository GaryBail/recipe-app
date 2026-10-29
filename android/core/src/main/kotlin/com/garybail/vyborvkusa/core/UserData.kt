package com.garybail.vyborvkusa.core

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * Всё, что пользователь создал у себя на телефоне: сборки, избранное, список покупок, настройки.
 * Хранится одним JSON-файлом (каталог рецептов в нём не дублируется — он берётся из seed.json).
 * Новые поля добавлять только со значением по умолчанию — тогда старый файл читается без потерь.
 */
@Serializable
data class UserData(
    val builds: List<Build> = emptyList(),
    /** recipeId → когда добавлен в избранное (мс). */
    val favorites: Map<String, Long> = emptyMap(),
    val shopping: List<ShoppingItem> = emptyList(),
    val settings: Settings = Settings(),
    /** Порции, выбранные на странице рецепта: recipeId → порции. */
    val recipeServings: Map<String, Int> = emptyMap(),
    /** Свои рецепты и рецепты, сохранённые из сообщества (id начинается с «user-»). */
    val userRecipes: List<CommunityRecipe> = emptyList(),
    /** Продукты, которых нет в каталоге: свои и из чужих сборок. */
    val userProducts: List<CommunityProduct> = emptyList(),
    /** id уведомлений, о которых уже показали системное уведомление. */
    val notifiedIds: List<Long> = emptyList(),
) {
    fun isFavorite(recipeId: String) = recipeId in favorites

    companion object {
        val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

        fun decode(text: String): UserData = json.decodeFromString(serializer(), text)
    }

    fun encode(): String = json.encodeToString(serializer(), this)
}

@Serializable
data class Settings(
    /** Город по умолчанию — Санкт-Петербург: там сильнее всего представлена Лента. */
    val cityId: String = DEFAULT_CITY_ID,
    /** Свой адрес сервера (для тестовых сборок); пусто — встроенный. */
    val serverUrl: String = "",
    val allergens: Set<String> = emptySet(),
    val vegetarian: Boolean = false,
    val dailyKcal: Int = 2000,
    val storeMode: Boolean = false,
) {
    val diet: DietProfile
        get() = DietProfile(allergens.mapNotNull { Allergen.fromRaw(it) }.toSet(), vegetarian)

    companion object {
        const val DEFAULT_CITY_ID = "spb"
    }
}

/** Сборка: рецепт + выбранный пользователем продукт для каждого ингредиента. */
@Serializable
data class Build(
    val id: String,
    val name: String,
    val recipeId: String,
    /** ingredientId → productId */
    val selection: Map<String, String>,
    val createdAt: Long,
    /** Сколько порций готовим по сборке (null — как в рецепте). */
    val servings: Int? = null,
    /** Включено слежение за ценой (подписка на сервере, id подписки = id сборки). */
    val isWatched: Boolean = false,
    /** id опубликованной копии в сообществе. */
    val remoteId: String? = null,
    /** Сборка сохранена из сообщества: чья и откуда. */
    val authorName: String? = null,
    val sourceRemoteId: String? = null,
) {
    fun effectiveServings(recipe: Recipe) = servings ?: recipe.servings

    fun product(ingredient: Ingredient, catalog: Catalog): Product? = selection[ingredient.id]?.let(catalog::product)

    /** Позиции корзины для сравнения цен (с учётом порций сборки). */
    fun cartLines(catalog: Catalog): List<CartLine> {
        val recipe = catalog.recipe(recipeId) ?: return emptyList()
        return recipe.ingredients.mapNotNull { ingredient ->
            val product = product(ingredient, catalog) ?: return@mapNotNull null
            CartLine(product.id, product.barcode, product.displayName,
                     recipe.scaledAmount(ingredient, effectiveServings(recipe)), ingredient.unit)
        }
    }

    fun nutrition(catalog: Catalog): NutritionSummary {
        val recipe = catalog.recipe(recipeId) ?: return NutritionSummary(Nutrition.ZERO, 0.0, emptyList())
        return NutritionCalculator.summary(recipe.ingredients.map {
            NutritionLine(it.title, it.amount, it.unit, product(it, catalog))
        })
    }
}

/** Строка списка покупок. Собирается из сборок и рецептов; одинаковые продукты складываются. */
@Serializable
data class ShoppingItem(
    val id: String,
    /** Что купить: продукт («Пармезан · Galbani») или ингредиент («Твёрдый сыр»). */
    val title: String,
    val categoryId: String,
    val productId: String? = null,
    val amount: Double,
    val unit: String,
    val isChecked: Boolean = false,
    val createdAt: Long,
    /** Для каких рецептов. */
    val sources: List<String> = emptyList(),
) {
    val measure: MeasureUnit get() = MeasureUnit.fromRaw(unit)
    val amountText: String get() = measure.format(amount)
    val mergeKey: String get() = ShoppingList.mergeKey(productId, categoryId, measure)
}
