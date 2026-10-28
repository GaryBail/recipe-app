package com.garybail.vyborvkusa.core

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * Каталог из seed.json — того же файла, что в iOS-приложении (RecipeApp/Resources/seed.json).
 * Читается один раз за запуск; все экраны берут рецепты, продукты и справочники отсюда.
 */
class Catalog(
    val version: Int,
    val recipes: List<Recipe>,
    val products: List<Product>,
    val rubrics: List<Rubric>,
    val cuisines: List<Cuisine>,
    val departments: List<String>,
    categories: List<CategoryInfo>,
) {
    val categories: Map<String, CategoryInfo> = categories.associateBy { it.id }
    val recipesById: Map<String, Recipe> = recipes.associateBy { it.id }
    val productsById: Map<String, Product> = products.associateBy { it.id }
    /** Продукты категории в порядке каталога: первым идёт основной вариант (как в iOS). */
    val productsByCategory: Map<String, List<Product>> = products.groupBy { it.categoryId }

    private val tagIndex: Map<String, Set<String>> = index { it.tags }
    private val allergenIndex: Map<String, Set<String>> = index { it.allergens }

    private fun index(values: (CategoryInfo) -> List<String>): Map<String, Set<String>> {
        val result = mutableMapOf<String, MutableSet<String>>()
        for (info in this.categories.values) for (v in values(info)) result.getOrPut(v) { mutableSetOf() }.add(info.id)
        return result
    }

    fun recipe(id: String): Recipe? = recipesById[id]
    fun product(id: String): Product? = productsById[id]
    fun category(id: String): CategoryInfo? = categories[id]
    fun rubric(id: String): Rubric? = rubrics.firstOrNull { it.id == id }
    fun cuisine(id: String): Cuisine? = cuisines.firstOrNull { it.id == id }

    /** Категории с признаком: "meat", "fish", "animal", "staple". */
    fun categoriesTagged(tag: String): Set<String> = tagIndex[tag].orEmpty()

    /** Категории, в которых есть аллерген ("milk", "gluten"…). */
    fun categoriesWithAllergen(allergen: String): Set<String> = allergenIndex[allergen].orEmpty()

    /** Отдел магазина для списка покупок. Неизвестные категории — в «Другое». */
    fun department(categoryId: String): Pair<Int, String> {
        val last = maxOf(departments.size - 1, 0)
        val order = categories[categoryId]?.department ?: last
        return order to (departments.getOrNull(order) ?: "Другое")
    }

    /** Название категории: из каталога, иначе из названия ингредиента. */
    fun categoryTitle(categoryId: String): String =
        categories[categoryId]?.title
            ?: recipes.asSequence().flatMap { it.ingredients }.firstOrNull { it.categoryId == categoryId }?.title
            ?: categoryId

    companion object {
        private val json = Json { ignoreUnknownKeys = true }

        fun parse(text: String): Catalog {
            val seed = json.decodeFromString(SeedFile.serializer(), text)
            return Catalog(
                version = seed.version ?: 1,
                recipes = seed.recipes.map { r ->
                    Recipe(
                        id = r.id, title = r.title, summary = r.summary, servings = r.servings, steps = r.steps,
                        ingredients = r.ingredients.mapIndexed { i, x ->
                            Ingredient(x.id, x.title, x.categoryId, x.amount, MeasureUnit.fromRaw(x.unit), i)
                        },
                        rubric = r.category.orEmpty(), cuisine = r.cuisine.orEmpty(),
                        cookMinutes = r.cookMinutes ?: 0, icon = r.icon.orEmpty(), featured = r.featured ?: false,
                    )
                },
                products = seed.products.map { p ->
                    Product(
                        id = p.id, name = p.name, brand = p.brand, categoryId = p.categoryId, barcode = p.barcode,
                        nutrition = p.nutrition?.let { Nutrition(it.kcal, it.protein, it.fat, it.carbs) },
                        gramsPerPiece = p.gramsPerPiece, density = p.density,
                    )
                },
                rubrics = seed.rubrics.orEmpty().map { Rubric(it.id, it.title, it.icon) },
                cuisines = seed.cuisines.orEmpty().map { Cuisine(it.id, it.title, it.icon) },
                departments = seed.departments ?: listOf("Другое"),
                categories = seed.categories.orEmpty().map {
                    CategoryInfo(it.id, it.title, it.department, it.allergens.orEmpty(), it.tags.orEmpty())
                },
            )
        }
    }
}

// --- Формат seed.json ---

@Serializable
internal class SeedFile(
    val version: Int? = null,
    val rubrics: List<RubricDTO>? = null,
    val cuisines: List<CuisineDTO>? = null,
    val departments: List<String>? = null,
    val categories: List<CategoryDTO>? = null,
    val products: List<ProductDTO>,
    val recipes: List<RecipeDTO>,
)

@Serializable
internal class RubricDTO(val id: String, val title: String, val icon: String? = null)

@Serializable
internal class CuisineDTO(val id: String, val title: String, val icon: String)

@Serializable
internal class CategoryDTO(
    val id: String,
    val title: String,
    val department: Int? = null,
    val allergens: List<String>? = null,
    val tags: List<String>? = null,
)

@Serializable
internal class NutritionDTO(val kcal: Double, val protein: Double, val fat: Double, val carbs: Double)

@Serializable
internal class ProductDTO(
    val id: String,
    val name: String,
    val brand: String? = null,
    val categoryId: String,
    val barcode: String? = null,
    val nutrition: NutritionDTO? = null,
    val gramsPerPiece: Double? = null,
    val density: Double? = null,
)

@Serializable
internal class IngredientDTO(
    val id: String,
    val title: String,
    val categoryId: String,
    val amount: Double,
    val unit: String,
)

@Serializable
internal class RecipeDTO(
    val id: String,
    val title: String,
    val summary: String,
    val servings: Int,
    val steps: List<String>,
    val ingredients: List<IngredientDTO>,
    val category: String? = null,
    val cookMinutes: Int? = null,
    val featured: Boolean? = null,
    val icon: String? = null,
    val cuisine: String? = null,
)
