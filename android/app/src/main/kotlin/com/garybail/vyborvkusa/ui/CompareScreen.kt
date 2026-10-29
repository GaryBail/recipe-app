package com.garybail.vyborvkusa.ui

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.garybail.vyborvkusa.AppModel
import com.garybail.vyborvkusa.core.CartQuote
import com.garybail.vyborvkusa.core.CartTransfer
import com.garybail.vyborvkusa.core.City
import com.garybail.vyborvkusa.core.compareCarts
import kotlinx.coroutines.launch

/** Сравнение корзины сборки по магазинам города: сначала полные корзины, затем по цене. */
@Composable
fun CompareScreen(model: AppModel, loaded: AppModel.Loaded, nav: Nav, buildId: String) {
    val build = model.data.builds.firstOrNull { it.id == buildId } ?: return
    val ant = Ant.colors
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val provider = remember(model.serverUrl) { model.priceProvider }
    val cityId = model.data.settings.cityId
    val lines = remember(build) { build.cartLines(loaded.catalog) }
    var cities by remember { mutableStateOf<List<City>>(emptyList()) }
    var quotes by remember { mutableStateOf<List<CartQuote>?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var expanded by remember { mutableStateOf<String?>(null) }
    var attempt by remember { mutableStateOf(0) }

    LaunchedEffect(provider, cityId, lines, attempt) {
        quotes = null
        error = null
        try {
            if (cities.isEmpty()) cities = provider.cities()
            val city = cities.firstOrNull { it.id == cityId } ?: cities.firstOrNull() ?: City(cityId, cityId)
            quotes = compareCarts(provider, lines, city)
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: Exception) {
            error = "Не удалось получить цены: ${e.message ?: "нет связи с сервером"}"
        }
    }

    ScreenScaffold("Где купить", onBack = { nav.back() }) { padding ->
        LazyColumn(Modifier.padding(padding).fillMaxSize().testTag("compare-list"),
                   contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            item {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("${build.name} · ${lines.size} продуктов", color = ant.textSecondary)
                    if (cities.isNotEmpty()) {
                        LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            items(cities) { c ->
                                AntCheckableTag(c.name, c.id == cityId, { model.updateSettings { it.copy(cityId = c.id) } })
                            }
                        }
                    }
                    if (model.serverUrl == null) {
                        AntTag("Тестовые цены — сервер не подключён", ant.gold)
                    }
                }
            }
            when {
                error != null -> item {
                    Column {
                        Text(error.orEmpty(), color = ant.error)
                        Spacer(Modifier.height(8.dp))
                        OutlinedButton(onClick = { attempt++ }) { Text("Повторить") }
                    }
                }
                quotes == null -> item {
                    Column(Modifier.fillMaxWidth().padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                        CircularProgressIndicator()
                        Spacer(Modifier.height(12.dp))
                        Text("Спрашиваем цены в магазинах…", color = ant.textSecondary)
                    }
                }
                quotes.orEmpty().isEmpty() -> item {
                    Text("В этом городе пока нет магазинов с доставкой.", color = ant.textSecondary)
                }
                else -> items(quotes.orEmpty(), key = { it.store.id }) { q ->
                    val best = q == quotes.orEmpty().first() && q.isComplete
                    QuoteCard(q, best, expanded == q.store.id,
                              onToggle = { expanded = if (expanded == q.store.id) null else q.store.id },
                              onOpenCart = {
                                  scope.launch {
                                      val url = runCatching { provider.cartLink(q) }.getOrNull() ?: q.store.webUrl
                                      if (url != null) context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                                  }
                              })
                }
            }
        }
    }
}

@Composable
private fun QuoteCard(q: CartQuote, best: Boolean, expanded: Boolean, onToggle: () -> Unit, onOpenCart: () -> Unit) {
    val ant = Ant.colors
    AntCard(Modifier.clickable(onClick = onToggle).testTag("quote-${q.store.id}")) {
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(q.store.name, fontWeight = FontWeight.SemiBold, fontSize = 17.sp, color = ant.text)
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        if (best) AntTag("Дешевле всего", ant.green)
                        if (!q.isComplete) AntTag("Нет ${q.missing.size} из ${q.lines.size + q.missing.size}", ant.orange)
                        if (q.store.id in CartTransfer.stores) AntTag("корзина целиком", ant.purple)
                    }
                }
                Text(if (q.lines.isEmpty()) "—" else rub(q.total), fontWeight = FontWeight.Bold, fontSize = 20.sp,
                     color = if (best) ant.green.text else ant.text)
            }
            val delivery = when {
                q.store.deliveryNote != null -> q.store.deliveryNote!!
                q.deliveryFee.signum() == 0 -> "Доставка бесплатно"
                else -> "Доставка ${rub(q.deliveryFee)}"
            }
            Text(delivery, fontSize = 13.sp, color = ant.textSecondary)
            if (q.minOrderShortfall.signum() > 0) {
                Text("До минимального заказа не хватает ${rub(q.minOrderShortfall)}", fontSize = 13.sp, color = ant.orange.text)
            }
            if (expanded) {
                q.lines.forEach { l ->
                    HorizontalDivider(color = ant.borderSecondary)
                    Row(Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
                        Column(Modifier.weight(1f)) {
                            Text(l.offer.title ?: l.line.title, color = ant.text, fontSize = 14.sp)
                            val qty = if (l.offer.isWeighted) l.line.unit.format(l.line.requiredAmount)
                                      else "${l.packages} уп. × ${l.offer.unit.format(l.offer.packageAmount)}"
                            Text("${l.line.title} · $qty", fontSize = 12.sp, color = ant.textTertiary)
                        }
                        Text(rub(l.cost), color = ant.text)
                    }
                }
                q.missing.forEach { m ->
                    HorizontalDivider(color = ant.borderSecondary)
                    Text("Нет в наличии: ${m.title}", fontSize = 13.sp, color = ant.orange.text,
                         modifier = Modifier.padding(vertical = 4.dp))
                }
                Spacer(Modifier.height(4.dp))
                Box(Modifier.fillMaxWidth()) {
                    if (q.store.id in CartTransfer.stores) {
                        Button(onClick = onOpenCart, modifier = Modifier.fillMaxWidth()) {
                            Text("Открыть корзину в «${q.store.name}»")
                        }
                    } else if (q.store.webUrl != null) {
                        OutlinedButton(onClick = onOpenCart, modifier = Modifier.fillMaxWidth()) {
                            Text("Открыть сайт магазина")
                        }
                    }
                }
            } else {
                Text("Подробнее", fontSize = 13.sp, color = ant.primary)
            }
        }
    }
}
