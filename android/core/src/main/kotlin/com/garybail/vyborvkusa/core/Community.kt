package com.garybail.vyborvkusa.core

import java.net.URLEncoder
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer

// ---------- Формат сервера (snake_case переводится автоматически) ----------

@Serializable
data class CommunityIngredient(val id: String, val title: String, val categoryId: String, val amount: Double,
                               val unit: String)

@Serializable
data class CommunityRecipe(
    val id: String,
    val title: String,
    val summary: String = "",
    val servings: Int,
    val steps: List<String> = emptyList(),
    val ingredients: List<CommunityIngredient>,
    val rubric: String? = null,
    val cookMinutes: Int? = null,
) {
    /** Рецепт в формате приложения (для своих рецептов из сообщества). */
    fun toRecipe(): Recipe = Recipe(
        id, title, summary, servings, steps,
        ingredients.mapIndexed { i, x -> Ingredient(x.id, x.title, x.categoryId, x.amount, MeasureUnit.fromRaw(x.unit), i) },
        rubric = rubric.orEmpty(), cookMinutes = cookMinutes ?: 0, icon = "shallow-pan-of-food",
        isUserCreated = id.startsWith("user-"),
    )

    companion object {
        fun from(recipe: Recipe) = CommunityRecipe(
            recipe.id, recipe.title, recipe.summary, recipe.servings, recipe.steps,
            recipe.ingredients.map { CommunityIngredient(it.id, it.title, it.categoryId, it.amount, it.unit.raw) },
            recipe.rubric.ifEmpty { null }, recipe.cookMinutes.takeIf { it > 0 },
        )
    }
}

@Serializable
data class CommunityProduct(val id: String, val name: String, val brand: String? = null, val categoryId: String,
                            val barcode: String? = null) {
    val displayName: String get() = if (!brand.isNullOrEmpty()) "$name · $brand" else name

    fun toProduct() = Product(id, name, brand, categoryId, barcode)
}

@Serializable
data class CommunityItem(val ingredientId: String, val product: CommunityProduct)

@Serializable
data class PublishRequest(val name: String, val recipe: CommunityRecipe, val items: List<CommunityItem>)

@Serializable
data class CommunityBuild(
    val id: String,
    val authorId: String,
    val authorName: String,
    val name: String,
    val createdAt: String,
    val recipe: CommunityRecipe,
    val items: List<CommunityItem>,
    val ratingAvg: Double? = null,
    val ratingCount: Int = 0,
    val score: Double = 0.0,
    val myRating: Int? = null,
) {
    fun product(ingredientId: String): CommunityProduct? = items.firstOrNull { it.ingredientId == ingredientId }?.product

    /** Позиции корзины — сравнить цены чужой сборки, не сохраняя её. */
    val cartLines: List<CartLine>
        get() = recipe.ingredients.mapNotNull { i ->
            val p = product(i.id) ?: return@mapNotNull null
            CartLine(p.id, p.barcode, p.displayName, i.amount, MeasureUnit.fromRaw(i.unit))
        }
}

@Serializable
data class CommunityRecipeEntry(
    val recipe: CommunityRecipe,
    val authorId: String,
    val authorName: String,
    val createdAt: String,
    val buildsCount: Int = 0,
    val ratingAvg: Double? = null,
    val ratingCount: Int = 0,
    val bestBuildId: String,
)

@Serializable
data class Choice(val product: CommunityProduct, val count: Int)

@Serializable
data class Choices(val recipeId: String, val builds: Int = 0, val ingredients: Map<String, List<Choice>> = emptyMap())

@Serializable
data class CommunityRating(val userId: String, val authorName: String, val stars: Int, val comment: String? = null,
                           val createdAt: String)

@Serializable
data class AppNotification(
    val id: Long,
    val kind: String,
    val buildId: String? = null,
    val buildName: String? = null,
    val actorName: String? = null,
    val stars: Int? = null,
    val comment: String? = null,
    val title: String,
    val body: String,
    val createdAt: String,
    val isRead: Boolean = false,
) {
    /** Уведомление о цене своей сборки (build_id — локальный id сборки), остальные — о сборке в сообществе. */
    val isAboutPrice: Boolean get() = kind == "price_drop" || kind == "reminder"
}

@Serializable
data class NotificationList(val items: List<AppNotification> = emptyList(), val unreadCount: Int = 0)

// ---------- Клиент ----------

class CommunityApi(private val api: ApiClient) {
    enum class Sort(val raw: String, val title: String) { TOP("top", "Лучшие"), NEW("new", "Новые") }

    @Serializable
    private class RatingBody(val stars: Int, val comment: String?)

    @Serializable
    private class ReasonBody(val reason: String)

    @Serializable
    private class BlockBody(val userId: String)

    @Serializable
    private class ReadBody(val ids: List<Long>)

    private fun enc(s: String) = URLEncoder.encode(s, "UTF-8")
    private val buildSerializer = CommunityBuild.serializer()

    suspend fun builds(sort: Sort = Sort.TOP, recipeId: String? = null, mine: Boolean = false): List<CommunityBuild> {
        val query = buildString {
            append("sort=${sort.raw}")
            recipeId?.let { append("&recipe_id=${enc(it)}") }
            if (mine) append("&mine=true")
        }
        return api.json.decodeFromString(ListSerializer(buildSerializer), api.send("GET", "community/builds?$query"))
    }

    suspend fun recipes(sort: Sort = Sort.TOP): List<CommunityRecipeEntry> = api.json.decodeFromString(
        ListSerializer(CommunityRecipeEntry.serializer()), api.send("GET", "community/recipes?sort=${sort.raw}"))

    suspend fun choices(recipeId: String): Choices =
        api.json.decodeFromString(Choices.serializer(), api.send("GET", "community/recipes/${enc(recipeId)}/choices"))

    suspend fun build(id: String): CommunityBuild =
        api.json.decodeFromString(buildSerializer, api.send("GET", "community/builds/${enc(id)}"))

    suspend fun publish(request: PublishRequest): CommunityBuild = api.json.decodeFromString(
        buildSerializer, api.send("POST", "community/builds", api.json.encodeToString(PublishRequest.serializer(), request)))

    suspend fun delete(id: String) {
        api.send("DELETE", "community/builds/${enc(id)}")
    }

    suspend fun ratings(buildId: String): List<CommunityRating> = api.json.decodeFromString(
        ListSerializer(CommunityRating.serializer()), api.send("GET", "community/builds/${enc(buildId)}/ratings"))

    suspend fun rate(buildId: String, stars: Int, comment: String?): CommunityBuild = api.json.decodeFromString(
        buildSerializer, api.send("PUT", "community/builds/${enc(buildId)}/rating",
                                  api.json.encodeToString(RatingBody.serializer(), RatingBody(stars, comment?.trim()?.ifEmpty { null }))))

    suspend fun report(buildId: String, reason: String) {
        api.send("POST", "community/builds/${enc(buildId)}/report", api.json.encodeToString(ReasonBody.serializer(), ReasonBody(reason)))
    }

    suspend fun block(userId: String) {
        api.send("POST", "community/blocks", api.json.encodeToString(BlockBody.serializer(), BlockBody(userId)))
    }

    suspend fun notifications(): NotificationList =
        api.json.decodeFromString(NotificationList.serializer(), api.send("GET", "notifications"))

    suspend fun markRead(ids: List<Long>) {
        if (ids.isNotEmpty()) api.send("POST", "notifications/read", api.json.encodeToString(ReadBody.serializer(), ReadBody(ids)))
    }

    companion object {
        /** Запрос на публикацию своей сборки: рецепт (свой или из каталога) + выбранные продукты. */
        fun publishRequest(build: Build, recipe: Recipe, catalog: Catalog, userProducts: List<Product> = emptyList()):
            PublishRequest? {
            val products = userProducts.associateBy { it.id }
            val items = recipe.ingredients.mapNotNull { ing ->
                val id = build.selection[ing.id] ?: return@mapNotNull null
                val p = catalog.product(id) ?: products[id] ?: return@mapNotNull null
                CommunityItem(ing.id, CommunityProduct(p.id, p.name, p.brand, p.categoryId, p.barcode))
            }
            return if (items.isEmpty()) null else PublishRequest(build.name, CommunityRecipe.from(recipe), items)
        }
    }
}
