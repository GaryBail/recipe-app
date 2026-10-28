package com.garybail.vyborvkusa.core

import java.time.LocalDate
import java.time.temporal.WeekFields
import java.util.Locale
import java.util.UUID

// ---------- Список покупок ----------

/** Позиция для добавления в список (до объединения с тем, что уже есть). */
data class ShoppingEntry(
    val title: String,
    val categoryId: String,
    val productId: String?,
    val amount: Double,
    val unit: MeasureUnit,
    val source: String,
)

object ShoppingList {
    fun mergeKey(productId: String?, categoryId: String, unit: MeasureUnit) =
        "${productId ?: "cat:$categoryId"}|${unit.raw}"

    /** Продукты сборки с учётом её порций. */
    fun entries(build: Build, catalog: Catalog): List<ShoppingEntry> {
        val recipe = catalog.recipe(build.recipeId) ?: return emptyList()
        return recipe.ingredients.map { ingredient ->
            val product = build.product(ingredient, catalog)
            ShoppingEntry(product?.displayName ?: ingredient.title, ingredient.categoryId, product?.id,
                          recipe.scaledAmount(ingredient, build.effectiveServings(recipe)), ingredient.unit,
                          recipe.title)
        }
    }

    /** Ингредиенты рецепта без выбранных продуктов. */
    fun entries(recipe: Recipe, servings: Int): List<ShoppingEntry> = recipe.ingredients.map {
        ShoppingEntry(it.title, it.categoryId, null, recipe.scaledAmount(it, servings), it.unit, recipe.title)
    }

    /**
     * Добавляет позиции: одинаковые продукты (или ингредиенты одной категории) складываются,
     * уже купленная позиция снова становится некупленной — на новое количество.
     */
    fun add(entries: List<ShoppingEntry>, existing: List<ShoppingItem>, now: Long = System.currentTimeMillis()):
        List<ShoppingItem> {
        val result = existing.toMutableList()
        for (entry in entries) {
            val key = mergeKey(entry.productId, entry.categoryId, entry.unit)
            val index = result.indexOfFirst { it.mergeKey == key }
            if (index >= 0) {
                val item = result[index]
                result[index] = item.copy(
                    amount = if (item.isChecked) entry.amount else item.amount + entry.amount,
                    isChecked = false,
                    sources = if (entry.source in item.sources) item.sources else item.sources + entry.source,
                )
            } else {
                result += ShoppingItem(UUID.randomUUID().toString(), entry.title, entry.categoryId, entry.productId,
                                       entry.amount, entry.unit.raw, false, now, listOf(entry.source))
            }
        }
        return result
    }

    fun shareText(items: List<ShoppingItem>, catalog: Catalog): String {
        val lines = mutableListOf("🛒 Список покупок", "")
        val groups = items.filter { !it.isChecked }.groupBy { catalog.department(it.categoryId).first }
        for (order in groups.keys.sorted()) {
            val group = groups.getValue(order)
            lines += catalog.department(group[0].categoryId).second + ":"
            for (item in group.sortedWith(compareBy(RU_COLLATOR) { it.title })) {
                lines += "☐ ${item.title} — ${item.amountText}"
            }
            lines += ""
        }
        lines += "Собрано в приложении «ВыборВкуса»"
        return lines.joinToString("\n")
    }
}

// ---------- «Из того, что есть» ----------

class FridgeMatcher(private val catalog: Catalog) {
    /** То, что почти всегда есть дома (признак "staple"): соль, специи, масло, сахар. */
    val staples: Set<String> = catalog.categoriesTagged("staple")

    data class Result(val recipe: Recipe, val have: List<Ingredient>, val missing: List<Ingredient>) {
        val total get() = have.size + missing.size
        val score get() = if (total == 0) 0.0 else have.size.toDouble() / total
        val isComplete get() = missing.isEmpty()
    }

    /** Рецепты, где есть хотя бы половина продуктов (или не хватает не больше двух); сначала — где хватает всего. */
    fun match(recipes: List<Recipe>, available: Set<String>, assumeStaples: Boolean = true): List<Result> {
        val have = if (assumeStaples) available + staples else available
        return recipes.mapNotNull { recipe ->
            if (recipe.ingredients.isEmpty()) return@mapNotNull null
            val haveList = recipe.ingredients.filter { it.categoryId in have }
            val missing = recipe.ingredients.filter { it.categoryId !in have }
            // Нужен хотя бы один отмеченный продукт, а не только «то, что всегда есть».
            if (haveList.none { it.categoryId in available }) return@mapNotNull null
            val result = Result(recipe, haveList, missing)
            if (result.score >= 0.5 || missing.size <= 2) result else null
        }.sortedWith(compareBy<Result> { it.missing.size }.thenByDescending { it.score }
            .thenBy(RU_COLLATOR) { it.recipe.title })
    }

    /** Поиск категорий по слову: «курица» → филе, бёдра, печень. */
    fun categories(query: String): List<Pair<String, String>> {
        val all = catalog.recipes.asSequence().flatMap { it.ingredients }.map { it.categoryId }
            .plus(catalog.products.map { it.categoryId }).distinct()
            .filter { it !in staples && !it.startsWith("user-") }
            .map { it to catalog.categoryTitle(it) }
            .sortedWith(compareBy(RU_COLLATOR) { it.second }).toList()
        val q = query.trim().lowercase()
        if (q.isEmpty()) return all
        val stem = q.take(maxOf(3, q.length - 2))
        fun rank(cat: Pair<String, String>): Int? {
            val title = cat.second.lowercase()
            return when {
                title.startsWith(stem) -> 0
                stem in title -> 1
                catalog.productsByCategory[cat.first].orEmpty().any { stem in it.name.lowercase() } -> 2
                else -> null
            }
        }
        return all.mapNotNull { cat -> rank(cat)?.let { cat to it } }
            .sortedWith(compareBy<Pair<Pair<String, String>, Int>> { it.second }.thenBy(RU_COLLATOR) { it.first.second })
            .map { it.first }
    }
}

// ---------- Подборки ----------

data class RecipeCollection(
    val id: String,
    val title: String,
    val subtitle: String,
    val icon: String,
    val palette: String,
    val recipeIds: List<String> = emptyList(),
) {
    /** Рецепты подборки. «Хиты недели» — популярное с сервера, иначе 8 рецептов по номеру недели. */
    fun recipes(all: List<Recipe>, traits: RecipeTraits, popularIds: List<String> = emptyList(),
                date: LocalDate = LocalDate.now()): List<Recipe> {
        val catalog = all.filter { !it.isUserCreated }
        val byId = catalog.associateBy { it.id }
        return when (id) {
            "week" -> {
                val popular = popularIds.mapNotNull { byId[it] }
                if (popular.size >= 4) return popular.take(10)
                val sorted = catalog.sortedBy { it.id }
                if (sorted.isEmpty()) return emptyList()
                val start = (weekNumber(date) * 7) % sorted.size
                (0 until minOf(8, sorted.size)).map { sorted[(start + it * 9) % sorted.size] }.distinctBy { it.id }
            }
            "quick" -> catalog.filter(traits::isQuick).sortedBy { it.cookMinutes }
            "lenten" -> catalog.filter(traits::isLenten)
            "family" -> catalog.filter { it.servings >= 6 }
            else -> recipeIds.mapNotNull { byId[it] }
        }
    }

    companion object {
        fun weekNumber(date: LocalDate): Int = date.get(WeekFields.of(Locale("ru")).weekOfWeekBasedYear())

        /** Сезонная подборка зависит от месяца. */
        fun seasonal(date: LocalDate = LocalDate.now()): RecipeCollection = when (date.monthValue) {
            12, 1, 2 -> RecipeCollection("winter", "Зимнее меню", "Сытно и празднично", "pot-of-food", "geekblue",
                listOf("borscht", "olivier", "herring-under-coat", "pelmeni", "solyanka", "pea-soup", "khachapuri",
                       "golubtsy", "raisin-cake", "goulash"))
            3, 4, 5 -> RecipeCollection("spring", "Весна", "Легче и свежее", "leafy-green", "green",
                listOf("shakshuka", "greek-salad", "summer-salad", "lentil-soup", "crab-salad", "baked-salmon",
                       "fried-eggs", "cabbage-salad", "rice-vegetables", "lazy-vareniki"))
            6, 7, 8 -> RecipeCollection("summer", "Лето", "Овощи с грядки и холодные супы", "tomato", "gold",
                listOf("okroshka", "summer-salad", "zucchini-fritters", "vegetable-stew", "ukha", "greek-salad",
                       "stuffed-peppers", "baked-salmon", "beet-garlic-salad", "shawarma"))
            else -> RecipeCollection("autumn", "Осень", "Тыква, грибы и яблоки", "brown-mushroom", "orange",
                listOf("pumpkin-soup", "millet-porridge", "mushroom-soup", "charlotte", "baked-apples", "shchi",
                       "rassolnik", "braised-cabbage", "fried-potatoes-mushrooms", "golubtsy", "cabbage-pies"))
        }

        val QUICK = RecipeCollection("quick", "Быстро", "До 30 минут", "egg", "cyan")
        val LENTEN = RecipeCollection("lenten", "Постное", "Без мяса, молока и яиц", "carrot", "green")
        val FAMILY = RecipeCollection("family", "На всю семью", "От 6 порций", "shallow-pan-of-food", "magenta")

        fun all(date: LocalDate = LocalDate.now()) = listOf(
            RecipeCollection("week", "Хиты недели", "Что готовят чаще всего", "cooking", "volcano"),
            seasonal(date), QUICK, LENTEN, FAMILY)
    }
}

// ---------- Таймеры в шагах рецепта ----------

object StepTimer {
    private val regex = Regex(
        """(\d+(?:[.,]\d+)?)(?:\s*[–—-]\s*(\d+(?:[.,]\d+)?))?\s*(час(?:а|ов)?|ч(?![а-яё])|минут[аы]?|мин(?![а-яё])|секунд)""",
        RegexOption.IGNORE_CASE)  // \b в Java не понимает кириллицу — граница слова через просмотр вперёд

    /** «варите 20 минут» → 1200 с, «1–1,5 часа» → 5400 с (верхняя граница); несколько — самое долгое. */
    fun duration(text: String): Long? {
        var best: Double? = null
        for (m in regex.findAll(text)) {
            val low = m.groupValues[1].replace(',', '.').toDoubleOrNull() ?: continue
            val value = m.groupValues[2].takeIf { it.isNotEmpty() }?.replace(',', '.')?.toDoubleOrNull() ?: low
            val unit = m.groupValues[3].lowercase()
            val seconds = when {
                unit.startsWith("ч") -> value * 3600
                unit.startsWith("сек") -> value
                else -> value * 60
            }
            if (seconds <= 0 || seconds > 12 * 3600) continue
            best = maxOf(best ?: 0.0, seconds)
        }
        return best?.toLong()
    }

    fun format(seconds: Long): String {
        val h = seconds / 3600
        val m = (seconds % 3600) / 60
        val s = seconds % 60
        return if (h > 0) String.format(Locale.US, "%d:%02d:%02d", h, m, s)
        else String.format(Locale.US, "%d:%02d", m, s)
    }
}
