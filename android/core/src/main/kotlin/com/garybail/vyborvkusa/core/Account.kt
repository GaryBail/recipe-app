package com.garybail.vyborvkusa.core

import java.net.HttpURLConnection
import java.net.URI
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNamingStrategy
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/** Ошибка сервера с текстом для пользователя (FastAPI: {"detail": "…"} или список ошибок проверки). */
class ApiException(val status: Int, message: String) : Exception(message)

/** HTTP-клиент нашего сервера: JSON в snake_case, токен сессии в заголовке. */
class ApiClient(private val baseUrl: String, val token: String?) {
    @OptIn(ExperimentalSerializationApi::class)
    val json = Json {
        ignoreUnknownKeys = true
        explicitNulls = false
        namingStrategy = JsonNamingStrategy.SnakeCase
    }

    suspend fun send(method: String, path: String, body: String? = null): String = withContext(Dispatchers.IO) {
        val connection = URI("$baseUrl/$path").toURL().openConnection() as HttpURLConnection
        try {
            connection.requestMethod = method
            connection.connectTimeout = 15_000
            connection.readTimeout = 30_000
            connection.setRequestProperty("Accept", "application/json")
            token?.let { connection.setRequestProperty("Authorization", "Bearer $it") }
            if (body != null) {
                connection.doOutput = true
                connection.setRequestProperty("Content-Type", "application/json; charset=utf-8")
                connection.outputStream.use { it.write(body.toByteArray()) }
            }
            val status = connection.responseCode
            val stream = if (status in 200..299) connection.inputStream else connection.errorStream
            val text = stream?.bufferedReader()?.use { it.readText() }.orEmpty()
            if (status !in 200..299) {
                throw ApiException(status, errorMessage(text) ?: if (status == 401) "Нужно войти в аккаунт."
                                                                 else "Ошибка сервера ($status)")
            }
            text
        } finally {
            connection.disconnect()
        }
    }

    companion object {
        /** Текст ошибки из ответа FastAPI. */
        fun errorMessage(text: String): String? = runCatching {
            when (val detail = Json.parseToJsonElement(text).jsonObject["detail"]) {
                is JsonPrimitive -> detail.contentOrNull
                is JsonArray -> detail.mapNotNull {
                    (it as? JsonObject)?.get("msg")?.jsonPrimitive?.contentOrNull?.removePrefix("Value error, ")
                }.joinToString("\n")
                else -> null
            }
        }.getOrNull()?.takeIf { it.isNotBlank() }
    }
}

@Serializable
data class Account(
    val id: String,
    val email: String? = null,
    val displayName: String,
    val cityId: String? = null,
    val hasApple: Boolean = false,
    val hasPassword: Boolean = true,
    val emailVerified: Boolean? = null,
    val priceAlerts: Boolean? = null,
) {
    val isEmailVerified: Boolean get() = emailVerified ?: hasApple
}

@Serializable
data class SessionResponse(val token: String, val user: Account, val created: Boolean = false)

/** Аккаунт: вход по почте и паролю, подтверждение почты, выход. */
class AuthApi(private val api: ApiClient) {
    @Serializable
    private class RegisterBody(val email: String, val password: String, val displayName: String, val cityId: String?)

    @Serializable
    private class LoginBody(val email: String, val password: String)

    @Serializable
    private class CodeBody(val code: String)

    @Serializable
    private class EmailBody(val email: String)

    @Serializable
    private class ResetBody(val email: String, val code: String, val newPassword: String)

    private inline fun <reified T> body(value: T) = api.json.encodeToString(kotlinx.serialization.serializer<T>(), value)
    private fun session(text: String) = api.json.decodeFromString(SessionResponse.serializer(), text)
    private fun account(text: String) = api.json.decodeFromString(Account.serializer(), text)

    suspend fun register(email: String, password: String, name: String, cityId: String?) =
        session(api.send("POST", "auth/register", body(RegisterBody(email.trim(), password, name.trim(), cityId))))

    suspend fun login(email: String, password: String) =
        session(api.send("POST", "auth/login", body(LoginBody(email.trim(), password))))

    suspend fun me() = account(api.send("GET", "auth/me"))

    suspend fun verifyEmail(code: String) = account(api.send("POST", "auth/verify-email", body(CodeBody(code.trim()))))

    suspend fun resendCode() {
        api.send("POST", "auth/verify-email/send")
    }

    suspend fun forgotPassword(email: String) {
        api.send("POST", "auth/password/forgot", body(EmailBody(email.trim())))
    }

    suspend fun resetPassword(email: String, code: String, newPassword: String) =
        session(api.send("POST", "auth/password/reset", body(ResetBody(email.trim(), code.trim(), newPassword))))

    suspend fun logout() {
        runCatching { api.send("POST", "auth/logout") }
    }
}

// ---------- Слежение за ценой ----------

@Serializable
data class StoreTotal(val storeId: String, val total: String, val complete: Boolean? = null, val missing: Int? = null)

@Serializable
data class Watch(
    val clientId: String,
    val name: String,
    val recipeTitle: String,
    val cityId: String,
    val checkedAt: String? = null,
    val best: StoreTotal? = null,
    val usualTotal: String? = null,
    val stores: List<StoreTotal> = emptyList(),
)

@Serializable
data class WatchLine(val productId: String, val query: String, val requiredAmount: Double, val unit: String)

@Serializable
data class WatchRequest(val name: String, val recipeTitle: String, val cityId: String, val lines: List<WatchLine>)

/** Сервер несколько раз в день пересчитывает корзину сборки и присылает напоминания, когда она дешевеет. */
class WatchApi(private val api: ApiClient) {
    suspend fun upsert(id: String, request: WatchRequest): Watch = api.json.decodeFromString(
        Watch.serializer(), api.send("PUT", "watches/$id", api.json.encodeToString(WatchRequest.serializer(), request)))

    suspend fun get(id: String): Watch = api.json.decodeFromString(Watch.serializer(), api.send("GET", "watches/$id"))

    suspend fun delete(id: String) {
        api.send("DELETE", "watches/$id")
    }

    companion object {
        /** Пока цены проверяются только в Петербурге (как на сервере, WATCH_CITIES). */
        const val SUPPORTED_CITY = Settings.DEFAULT_CITY_ID

        fun request(build: Build, catalog: Catalog): WatchRequest? {
            val recipe = catalog.recipe(build.recipeId) ?: return null
            val lines = build.cartLines(catalog).map {
                WatchLine(it.productId, RemotePriceProvider.searchQuery(it), it.requiredAmount, it.unit.raw)
            }
            return if (lines.isEmpty()) null else WatchRequest(build.name, recipe.title, SUPPORTED_CITY, lines)
        }

        /** Названия магазинов для подписи «дешевле всего в …». */
        fun storeName(id: String) = when (id) {
            "lenta" -> "Лента"
            "magnit" -> "Магнит"
            "auchan" -> "Ашан"
            "vkusvill" -> "ВкусВилл"
            "kuper" -> "Купер"
            else -> id
        }
    }
}
