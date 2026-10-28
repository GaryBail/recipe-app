package com.garybail.vyborvkusa.core

import java.io.IOException
import java.math.BigDecimal
import java.net.HttpURLConnection
import java.net.URI
import java.net.URLEncoder
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/** Адрес сервера: http(s) с хостом; иначе null. */
fun serverUrlOrNull(raw: String?): String? {
    val text = raw?.trim().orEmpty()
    if (text.isEmpty() || text.startsWith("$(")) return null
    return runCatching {
        val uri = URI(text)
        if (uri.scheme?.startsWith("http") == true && !uri.host.isNullOrEmpty()) text.trimEnd('/') else null
    }.getOrNull()
}

class ServerException(val status: Int, message: String) : IOException(message)

/** Цены через наш сервер (backend/), который опрашивает Ленту, Магнит, Ашан, ВкусВилл и Купер. */
class RemotePriceProvider(private val baseUrl: String) : PriceProvider {
    private val json = Json { ignoreUnknownKeys = true; explicitNulls = false }

    @Serializable
    private class CityDTO(val id: String, val name: String)

    @Serializable
    private class StoreDTO(
        val id: String,
        val name: String,
        @SerialName("delivery_fee") val deliveryFee: String = "0",
        @SerialName("free_delivery_from") val freeDeliveryFrom: String? = null,
        @SerialName("min_order") val minOrder: String = "0",
        @SerialName("delivery_note") val deliveryNote: String? = null,
        @SerialName("web_url") val webUrl: String? = null,
    )

    @Serializable
    internal class OfferDTO(
        val sku: String,
        val title: String,
        val price: String,
        @SerialName("package_amount") val packageAmount: Double,
        val unit: String,
        @SerialName("in_stock") val inStock: Boolean = true,
        @SerialName("is_weighted") val isWeighted: Boolean = false,
    )

    @Serializable
    internal class MatchDTO(val offer: OfferDTO)

    @Serializable
    internal class OffersResponse(val offers: Map<String, MatchDTO>)

    @Serializable
    private class LineDTO(
        @SerialName("product_id") val productId: String,
        val query: String,
        @SerialName("required_amount") val requiredAmount: Double,
        val unit: String,
    )

    @Serializable
    private class OffersRequest(val store: String, val city: String, val lines: List<LineDTO>)

    @Serializable
    private class CartItemDTO(val sku: String, val quantity: Double)

    @Serializable
    private class CartLinkRequest(val store: String, val items: List<CartItemDTO>)

    @Serializable
    private class CartLinkResponse(val url: String)

    override suspend fun cities(): List<City> =
        json.decodeFromString<List<CityDTO>>(request("GET", "cities")).map { City(it.id, it.name) }

    override suspend fun stores(city: City): List<Store> =
        json.decodeFromString<List<StoreDTO>>(request("GET", "stores?city=${enc(city.id)}")).map {
            Store(it.id, it.name, it.deliveryFee.toBigDecimalOrNull() ?: BigDecimal.ZERO,
                  it.freeDeliveryFrom?.toBigDecimalOrNull(), it.minOrder.toBigDecimalOrNull() ?: BigDecimal.ZERO,
                  it.webUrl, city.id, it.deliveryNote)
        }

    override suspend fun offers(lines: List<CartLine>, store: Store): Map<String, StoreOffer> {
        val body = OffersRequest(store.id, store.cityId.orEmpty(), lines.map {
            LineDTO(it.productId, searchQuery(it), it.requiredAmount, it.unit.raw)
        })
        return decodeOffers(request("POST", "offers", json.encodeToString(OffersRequest.serializer(), body)))
    }

    override suspend fun cartLink(quote: CartQuote): String? {
        if (quote.store.id !in CartTransfer.stores) return null
        val items = CartTransfer.items(quote).map { CartItemDTO(it.first, it.second) }
        if (items.isEmpty()) return null
        val body = json.encodeToString(CartLinkRequest.serializer(), CartLinkRequest(quote.store.id, items))
        return json.decodeFromString<CartLinkResponse>(request("POST", "cart-link", body)).url
    }

    internal fun decodeOffers(text: String): Map<String, StoreOffer> =
        json.decodeFromString<OffersResponse>(text).offers.mapNotNull { (productId, match) ->
            val o = match.offer
            val price = o.price.toBigDecimalOrNull() ?: return@mapNotNull null
            productId to StoreOffer(productId, price, o.packageAmount, MeasureUnit.fromRaw(o.unit), o.inStock,
                                    o.title, o.isWeighted, o.sku)
        }.toMap()

    private suspend fun request(method: String, path: String, body: String? = null): String =
        withContext(Dispatchers.IO) {
            val connection = URI("$baseUrl/$path").toURL().openConnection() as HttpURLConnection
            try {
                connection.requestMethod = method
                connection.connectTimeout = 15_000
                connection.readTimeout = 90_000
                connection.setRequestProperty("Accept", "application/json")
                if (body != null) {
                    connection.doOutput = true
                    connection.setRequestProperty("Content-Type", "application/json; charset=utf-8")
                    connection.outputStream.use { it.write(body.toByteArray()) }
                }
                val status = connection.responseCode
                val stream = if (status in 200..299) connection.inputStream else connection.errorStream
                val text = stream?.bufferedReader()?.use { it.readText() }.orEmpty()
                if (status !in 200..299) throw ServerException(status, "Сервер ответил с ошибкой $status")
                text
            } finally {
                connection.disconnect()
            }
        }

    companion object {
        /** «Спагетти №5 · Barilla» → «Спагетти №5 Barilla». */
        fun searchQuery(line: CartLine) = line.title.replace(" · ", " ")

        private fun enc(s: String) = URLEncoder.encode(s, "UTF-8")
    }
}

/** Тестовые магазины с предсказуемыми ценами — пока сервер не указан. */
class MockPriceProvider : PriceProvider {
    private val markup = mapOf("a" to 100, "b" to 92, "c" to 110)

    override suspend fun cities() = listOf(City("spb", "Санкт-Петербург"), City("msk", "Москва"),
                                           City("kzn", "Казань"))

    override suspend fun stores(city: City): List<Store> {
        val stores = mutableListOf(
            Store("a", "Магазин А", BigDecimal(199), BigDecimal(2000), BigDecimal(500), cityId = city.id),
            Store("b", "Магазин Б", BigDecimal(299), null, BigDecimal(1000), cityId = city.id),
        )
        if (city.id == "spb") stores += Store("c", "Магазин В", BigDecimal.ZERO, null, BigDecimal(1500), cityId = city.id)
        return stores
    }

    override suspend fun offers(lines: List<CartLine>, store: Store): Map<String, StoreOffer> {
        delay(300)  // имитация сети
        val k = markup[store.id] ?: 100
        return lines.mapNotNull { line ->
            val h = stableHash(line.productId + store.id)
            if (h % 9 == 0) return@mapNotNull null  // примерно каждого 9-го товара нет
            val pack = when (line.unit) {
                MeasureUnit.GRAMS -> listOf(100.0, 200.0, 250.0, 400.0, 500.0, 1000.0)[h % 6]
                MeasureUnit.MILLILITERS -> listOf(250.0, 500.0, 1000.0)[h % 3]
                MeasureUnit.PIECES -> listOf(1.0, 6.0, 10.0)[h % 3]
            }
            val base = 60 + stableHash(line.productId) % 400
            line.productId to StoreOffer(line.productId, BigDecimal(base * k / 100), pack, line.unit)
        }.toMap()
    }

    /** Как в iOS: djb2, чтобы цены совпадали на обеих платформах. */
    private fun stableHash(s: String): Int {
        var h = 5381L
        s.codePoints().forEach { h = (h * 33 + it) and 0x7fff_ffff }
        return h.toInt()
    }
}
