package com.garybail.vyborvkusa

import android.app.Application
import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.garybail.vyborvkusa.core.Account
import com.garybail.vyborvkusa.core.ApiClient
import com.garybail.vyborvkusa.core.ApiException
import com.garybail.vyborvkusa.core.AuthApi
import com.garybail.vyborvkusa.core.Build
import com.garybail.vyborvkusa.core.SessionResponse
import com.garybail.vyborvkusa.core.WatchApi
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

    // ---------- Аккаунт ----------
    // Токен — в личных настройках приложения (доступны только ему).
    private val prefs = app.getSharedPreferences("account", android.content.Context.MODE_PRIVATE)

    var account by mutableStateOf<Account?>(
        prefs.getString("user", null)?.let { runCatching { ApiClient("", null).json.decodeFromString(Account.serializer(), it) }.getOrNull() })
        private set

    private val token: String? get() = prefs.getString("token", null)

    /** Клиент сервера; null — адрес сервера не указан. */
    fun api(): ApiClient? = serverUrl?.let { ApiClient(it, token) }

    private fun requireApi(): ApiClient = api() ?: throw ApiException(0, "Укажите адрес сервера в профиле.")

    private fun storeSession(response: SessionResponse) {
        prefs.edit().putString("token", response.token).apply()
        storeAccount(response.user)
    }

    private fun storeAccount(user: Account) {
        account = user
        prefs.edit().putString("user", ApiClient("", null).json.encodeToString(Account.serializer(), user)).apply()
    }

    suspend fun register(email: String, password: String, name: String) =
        storeSession(AuthApi(requireApi()).register(email, password, name, data.settings.cityId))

    suspend fun login(email: String, password: String) = storeSession(AuthApi(requireApi()).login(email, password))

    suspend fun verifyEmail(code: String) = storeAccount(AuthApi(requireApi()).verifyEmail(code))

    suspend fun resendCode() = AuthApi(requireApi()).resendCode()

    suspend fun forgotPassword(email: String) = AuthApi(requireApi()).forgotPassword(email)

    suspend fun resetPassword(email: String, code: String, password: String) =
        storeSession(AuthApi(requireApi()).resetPassword(email, code, password))

    /** Проверка сессии при запуске: отозванный токен — выходим, нет сети — оставляем профиль. */
    fun refreshAccount() {
        val api = api() ?: return
        if (token == null) return
        scope.launch {
            try {
                storeAccount(AuthApi(api).me())
            } catch (e: ApiException) {
                if (e.status == 401) clearAccount()
            } catch (_: Exception) {
            }
        }
    }

    fun logout() {
        val api = api()
        scope.launch { api?.let { AuthApi(it).logout() } }
        clearAccount()
    }

    private fun clearAccount() {
        prefs.edit().clear().apply()
        account = null
        update { d -> d.copy(builds = d.builds.map { it.copy(isWatched = false) }) }
    }

    // ---------- Слежение за ценой ----------

    /** Включает/выключает подписку на цену сборки; ошибку возвращает текстом. */
    suspend fun setWatched(buildId: String, on: Boolean): String? {
        val loaded = loaded ?: return null
        val build = data.builds.firstOrNull { it.id == buildId } ?: return null
        val api = api() ?: return "Укажите адрес сервера в профиле."
        return try {
            if (on) {
                val request = WatchApi.request(build, loaded.catalog) ?: return "В сборке нет выбранных продуктов."
                WatchApi(api).upsert(buildId, request)
            } else {
                runCatching { WatchApi(api).delete(buildId) }
            }
            update { d -> d.copy(builds = d.builds.map { if (it.id == buildId) it.copy(isWatched = on) else it }) }
            null
        } catch (e: Exception) {
            e.message ?: "Не удалось связаться с сервером"
        }
    }

    suspend fun watch(buildId: String) = api()?.let { runCatching { WatchApi(it).get(buildId) }.getOrNull() }

    /** После изменения состава или порций — обновить подписку, если она включена. */
    private fun resyncWatch(buildId: String) {
        val build = data.builds.firstOrNull { it.id == buildId } ?: return
        val catalog = loaded?.catalog ?: return
        if (!build.isWatched) return
        val api = api() ?: return
        val request = WatchApi.request(build, catalog) ?: return
        scope.launch { runCatching { WatchApi(api).upsert(buildId, request) } }
    }

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
            refreshAccount()
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
        resyncWatch(id)
        return id
    }

    fun setBuildServings(id: String, servings: Int) {
        update { d -> d.copy(builds = d.builds.map { if (it.id == id) it.copy(servings = servings.coerceIn(1, 50)) else it }) }
        resyncWatch(id)
    }

    fun deleteBuild(id: String) {
        if (data.builds.firstOrNull { it.id == id }?.isWatched == true) {
            api()?.let { api -> scope.launch { runCatching { WatchApi(api).delete(id) } } }
        }
        update { d -> d.copy(builds = d.builds.filter { it.id != id }) }
    }

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
