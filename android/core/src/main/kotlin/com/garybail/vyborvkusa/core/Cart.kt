package com.garybail.vyborvkusa.core

import java.math.BigDecimal
import java.math.RoundingMode
import kotlin.math.ceil
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope

/** Город пользователя — от него зависит список магазинов. */
data class City(val id: String, val name: String)

/** Магазин с доставкой в выбранном городе. */
data class Store(
    val id: String,
    val name: String,
    val deliveryFee: BigDecimal = BigDecimal.ZERO,
    /** Сумма, от которой доставка бесплатная (если есть). */
    val freeDeliveryFrom: BigDecimal? = null,
    val minOrder: BigDecimal = BigDecimal.ZERO,
    val webUrl: String? = null,
    /** Город, для которого получен магазин (нужен серверу при запросе цен). */
    val cityId: String? = null,
    /** Пояснение к доставке, если точные условия неизвестны. */
    val deliveryNote: String? = null,
)

/** Позиция корзины: что нужно купить для сборки. */
data class CartLine(
    val productId: String,
    val barcode: String?,
    val title: String,
    val requiredAmount: Double,
    val unit: MeasureUnit,
)

/** Предложение магазина по конкретному продукту. */
data class StoreOffer(
    val productId: String,
    val price: BigDecimal,
    /** Фасовка товара в магазине (например, 250 г). */
    val packageAmount: Double,
    val unit: MeasureUnit,
    val inStock: Boolean = true,
    /** Название товара в магазине (что именно подобрано). */
    val title: String? = null,
    /** Весовой: цена за packageAmount, покупается ровно нужное количество. */
    val isWeighted: Boolean = false,
    /** Артикул в магазине — чтобы передать корзину. */
    val sku: String? = null,
)

/** Строка расчёта: сколько упаковок купить и за сколько. */
data class QuoteLine(val line: CartLine, val offer: StoreOffer, val packages: Int) {
    val cost: BigDecimal
        get() = if (offer.isWeighted && offer.unit == line.unit && offer.packageAmount > 0) {
            offer.price.multiply(BigDecimal(line.requiredAmount / offer.packageAmount)).setScale(2, RoundingMode.HALF_UP)
        } else {
            offer.price.multiply(BigDecimal(packages))
        }
}

/** Итог по одному магазину. */
data class CartQuote(
    val store: Store,
    val lines: List<QuoteLine>,
    val missing: List<CartLine>,
    val itemsTotal: BigDecimal,
    val deliveryFee: BigDecimal,
    /** Сколько не хватает до минимальной суммы заказа. */
    val minOrderShortfall: BigDecimal,
) {
    val total: BigDecimal get() = itemsTotal + deliveryFee
    val isComplete: Boolean get() = missing.isEmpty()
}

object CartComparator {
    /** Сколько целых упаковок нужно, чтобы покрыть требуемое количество. */
    fun packagesNeeded(required: Double, requiredUnit: MeasureUnit, offer: StoreOffer): Int {
        if (offer.unit != requiredUnit || offer.packageAmount <= 0) return 1
        return maxOf(1, ceil(required / offer.packageAmount - 1e-9).toInt())
    }

    fun quote(lines: List<CartLine>, store: Store, offers: Map<String, StoreOffer>): CartQuote {
        val quoteLines = mutableListOf<QuoteLine>()
        val missing = mutableListOf<CartLine>()
        for (line in lines) {
            val offer = offers[line.productId]
            if (offer == null || !offer.inStock) {
                missing += line
                continue
            }
            quoteLines += QuoteLine(line, offer, packagesNeeded(line.requiredAmount, line.unit, offer))
        }
        val itemsTotal = quoteLines.fold(BigDecimal.ZERO) { acc, l -> acc + l.cost }
        val free = store.freeDeliveryFrom
        val delivery = if (free != null && itemsTotal >= free) BigDecimal.ZERO else store.deliveryFee
        val shortfall = (store.minOrder - itemsTotal).max(BigDecimal.ZERO)
        return CartQuote(store, quoteLines, missing, itemsTotal, delivery, shortfall)
    }

    /** Сначала полные корзины, затем по числу недостающих, затем по итоговой цене. */
    fun rank(quotes: List<CartQuote>): List<CartQuote> =
        quotes.sortedWith(compareBy<CartQuote> { !it.isComplete }.thenBy { it.missing.size }.thenBy { it.total })
}

/** Что передаём в корзину магазина: артикул и количество (упаковки или кг для весового). */
object CartTransfer {
    val stores = setOf("vkusvill")

    fun items(quote: CartQuote): List<Pair<String, Double>> = quote.lines.mapNotNull { line ->
        val sku = line.offer.sku ?: return@mapNotNull null
        if (line.offer.isWeighted && line.offer.unit == line.line.unit && line.offer.packageAmount > 0) {
            // Килограммы с точностью до 10 г, округляя вверх (поправка на погрешность Double).
            val hundredths = ceil(line.line.requiredAmount / line.offer.packageAmount * 100 - 1e-9)
            sku to hundredths / 100
        } else {
            sku to line.packages.toDouble()
        }
    }
}

/** Источник цен: наш сервер или тестовые данные. */
interface PriceProvider {
    suspend fun cities(): List<City>
    suspend fun stores(city: City): List<Store>
    /** Предложения магазина по позициям корзины, ключ — productId. */
    suspend fun offers(lines: List<CartLine>, store: Store): Map<String, StoreOffer>
    /** Ссылка на готовую корзину в магазине; null — магазин так не умеет. */
    suspend fun cartLink(quote: CartQuote): String? = null
}

/** Опрашивает все магазины города параллельно и ранжирует корзины. Сбой одного магазина не мешает остальным. */
suspend fun compareCarts(provider: PriceProvider, lines: List<CartLine>, city: City): List<CartQuote> =
    coroutineScope {
        val stores = provider.stores(city)
        val quotes = stores.map { store ->
            async {
                runCatching { CartComparator.quote(lines, store, provider.offers(lines, store)) }.getOrNull()
            }
        }.mapNotNull { it.await() }
        CartComparator.rank(quotes)
    }
