package com.garybail.vyborvkusa

import android.app.Application
import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.garybail.vyborvkusa.core.Build
import com.garybail.vyborvkusa.core.Catalog
import com.garybail.vyborvkusa.core.MockPriceProvider
import com.garybail.vyborvkusa.core.NutritionIndex
import com.garybail.vyborvkusa.core.PriceProvider
import com.garybail.vyborvkusa.core.RecipeTraits
import com.garybail.vyborvkusa.core.RemotePriceProvider
import com.garybail.vyborvkusa.core.Settings
import com.garybail.vyborvkusa.core.ShoppingEntry
import com.garybail.vyborvkusa.core.ShoppingList
import com.garybail.vyborvkusa.core.UserData
import com.garybail.vyborvkusa.core.serverUrlOrNull
import java.io.File
import java.util.UUID
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/** Каталог, данные пользователя и действия над ними. Один на всё приложение. */
class AppModel(private val app: Application) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val file = File(app.filesDir, "user.json")
    private val saveLock = Mutex()
    private var saveJob: Job? = null

    /** Каталог и производные от него индексы — появляются после загрузки (доли секунды). */
    class Loaded(val catalog: Catalog) {
        val traits = RecipeTraits(catalog)
        val nutrition = NutritionIndex(catalog.products)
        /** Калорийность порции для карточек и фильтра «Лёгкое» — считается один раз. */
        val kcal: Map<String, Double?> = catalog.recipes.associate { it.id to nutrition.kcalPerServing(it) }
    }

    var loaded by mutableStateOf<Loaded?>(null)
        private set
    var data by mutableStateOf(UserData())
        private set

    init {
        scope.launch {
            val (catalog, user) = withContext(Dispatchers.IO) {
                val catalog = app.assets.open("seed.json").bufferedReader().use { Catalog.parse(it.readText()) }
                val user = runCatching { if (file.exists()) UserData.decode(file.readText()) else UserData() }
                    .onFailure { Log.e("VyborVkusa", "Не удалось прочитать данные, начинаем с пустых", it) }
                    .getOrElse {
                        runCatching { file.copyTo(File(app.filesDir, "user.broken.json"), overwrite = true) }  // не теряем
                        UserData()
                    }
                Loaded(catalog) to user
            }
            data = user
            loaded = catalog
        }
    }

    // ---------- Сохранение ----------

    fun update(transform: (UserData) -> UserData) {
        data = transform(data)
        val snapshot = data
        saveJob?.cancel()
        saveJob = scope.launch {
            delay(300)  // несколько быстрых изменений подряд — одна запись
            withContext(Dispatchers.IO) {
                saveLock.withLock {
                    val tmp = File(file.path + ".tmp")
                    tmp.writeText(snapshot.encode())
                    tmp.renameTo(file)
                }
            }
        }
    }

    // ---------- Сервер цен ----------

    /** Адрес сервера: свой из профиля (в тестовых сборках) или встроенный в сборку. */
    val serverUrl: String?
        get() = (if (BuildConfig.ALLOW_SERVER_OVERRIDE) serverUrlOrNull(data.settings.serverUrl) else null)
            ?: serverUrlOrNull(BuildConfig.SERVER_URL)

    val priceProvider: PriceProvider
        get() = serverUrl?.let(::RemotePriceProvider) ?: MockPriceProvider()

    // ---------- Действия ----------

    fun toggleFavorite(recipeId: String) = update {
        it.copy(favorites = if (recipeId in it.favorites) it.favorites - recipeId
                            else it.favorites + (recipeId to System.currentTimeMillis()))
    }

    fun setRecipeServings(recipeId: String, servings: Int) =
        update { it.copy(recipeServings = it.recipeServings + (recipeId to servings.coerceIn(1, 50))) }

    /** Сохраняет новую сборку или изменения существующей; возвращает id. */
    fun saveBuild(existingId: String?, name: String, recipeId: String, selection: Map<String, String>): String {
        val id = existingId ?: UUID.randomUUID().toString()
        update { d ->
            val old = d.builds.firstOrNull { it.id == id }
            val build = old?.copy(name = name, selection = selection)
                ?: Build(id, name, recipeId, selection, System.currentTimeMillis())
            d.copy(builds = if (old == null) listOf(build) + d.builds else d.builds.map { if (it.id == id) build else it })
        }
        return id
    }

    fun setBuildServings(id: String, servings: Int) = update { d ->
        d.copy(builds = d.builds.map { if (it.id == id) it.copy(servings = servings.coerceIn(1, 50)) else it })
    }

    fun deleteBuild(id: String) = update { d -> d.copy(builds = d.builds.filter { it.id != id }) }

    fun addToShopping(entries: List<ShoppingEntry>) =
        update { it.copy(shopping = ShoppingList.add(entries, it.shopping)) }

    fun toggleShopping(id: String) = update { d ->
        d.copy(shopping = d.shopping.map { if (it.id == id) it.copy(isChecked = !it.isChecked) else it })
    }

    fun removeShopping(id: String) = update { d -> d.copy(shopping = d.shopping.filter { it.id != id }) }

    fun removeCheckedShopping() = update { d -> d.copy(shopping = d.shopping.filter { !it.isChecked }) }

    fun clearShopping() = update { it.copy(shopping = emptyList()) }

    fun updateSettings(transform: (Settings) -> Settings) = update { it.copy(settings = transform(it.settings)) }
}
