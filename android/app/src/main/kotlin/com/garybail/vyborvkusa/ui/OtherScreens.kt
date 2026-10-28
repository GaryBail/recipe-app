package com.garybail.vyborvkusa.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.garybail.vyborvkusa.AppModel
import com.garybail.vyborvkusa.BuildConfig
import com.garybail.vyborvkusa.core.Allergen
import com.garybail.vyborvkusa.core.FridgeMatcher
import com.garybail.vyborvkusa.core.StepTimer
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// ---------- Избранное и мои сборки ----------

@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun FavoritesScreen(model: AppModel, loaded: AppModel.Loaded, nav: Nav) {
    var tab by rememberSaveable { mutableStateOf(0) }
    val data = model.data
    val favorites = data.favorites.entries.sortedByDescending { it.value }.mapNotNull { loaded.catalog.recipe(it.key) }
    ScreenScaffold("Избранное") { padding ->
        Column(Modifier.padding(padding)) {
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
                listOf("Рецепты", "Мои сборки").forEachIndexed { i, title ->
                    SegmentedButton(selected = tab == i, onClick = { tab = i },
                                    shape = SegmentedButtonDefaults.itemShape(i, 2)) { Text(title) }
                }
            }
            if (tab == 0) {
                if (favorites.isEmpty()) EmptyState("Пока пусто", "Нажмите ♡ на странице рецепта — он появится здесь.",
                                                    icon = "cooking")
                else RecipeGrid(favorites, loaded, nav)
            } else {
                if (data.builds.isEmpty()) {
                    EmptyState("Сборок нет", "Откройте рецепт и нажмите «Выбрать продукты».", icon = "shallow-pan-of-food")
                } else {
                    LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        items(data.builds, key = { it.id }) { b ->
                            val recipe = loaded.catalog.recipe(b.recipeId)
                            PressCard({ nav.build(b.id) }, Modifier.fillMaxWidth()) {
                                Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                                    FoodImage(recipe?.icon.orEmpty(), 44.dp)
                                    Spacer(Modifier.width(12.dp))
                                    Column {
                                        Text(b.name, fontWeight = FontWeight.SemiBold, color = Ant.colors.text)
                                        Text(recipe?.title.orEmpty(), fontSize = 13.sp, color = Ant.colors.textSecondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// ---------- Профиль ----------

private val knownCities = listOf("spb" to "Санкт-Петербург", "msk" to "Москва", "kzn" to "Казань",
                                 "ekb" to "Екатеринбург", "nsk" to "Новосибирск", "nnv" to "Нижний Новгород")

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ProfileScreen(model: AppModel) {
    val settings = model.data.settings
    val ant = Ant.colors
    var server by rememberSaveable { mutableStateOf(settings.serverUrl) }
    ScreenScaffold("Профиль") { padding ->
        LazyColumn(Modifier.padding(padding).fillMaxSize().testTag("profile"), contentPadding = PaddingValues(16.dp),
                   verticalArrangement = Arrangement.spacedBy(12.dp)) {
            item { SectionTitle("Город") }
            item {
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    knownCities.forEach { (id, name) ->
                        AntCheckableTag(name, settings.cityId == id, { model.updateSettings { it.copy(cityId = id) } })
                    }
                }
            }
            item { Text("Цены сравниваем в магазинах выбранного города: Лента, Магнит, Ашан, ВкусВилл и Купер.",
                        fontSize = 13.sp, color = ant.textSecondary) }
            item { SectionTitle("Аллергии и ограничения") }
            item {
                AntCard {
                    Column {
                        Allergen.entries.forEach { a ->
                            val on = a.raw in settings.allergens
                            Row(Modifier.fillMaxWidth().clickable {
                                model.updateSettings { it.copy(allergens = if (on) it.allergens - a.raw else it.allergens + a.raw) }
                            }, verticalAlignment = Alignment.CenterVertically) {
                                Checkbox(on, null)
                                Text(a.title, color = ant.text)
                            }
                        }
                        Row(Modifier.fillMaxWidth().padding(top = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text("Не ем мясо и рыбу", color = ant.text, modifier = Modifier.weight(1f).padding(start = 12.dp))
                            Switch(settings.vegetarian, { v -> model.updateSettings { it.copy(vegetarian = v) } })
                        }
                    }
                }
            }
            item { Text("Рецепты с этими продуктами получат предупреждение, а фильтр «Мне подходит» их скроет.",
                        fontSize = 13.sp, color = ant.textSecondary) }
            item {
                SectionTitle("Дневная норма") {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        OutlinedButton(onClick = { model.updateSettings { it.copy(dailyKcal = (it.dailyKcal - 100).coerceAtLeast(1200)) } }) { Text("−") }
                        Text("${settings.dailyKcal} ккал", modifier = Modifier.padding(horizontal = 8.dp), color = ant.text)
                        OutlinedButton(onClick = { model.updateSettings { it.copy(dailyKcal = (it.dailyKcal + 100).coerceAtMost(4000)) } }) { Text("+") }
                    }
                }
            }
            if (BuildConfig.ALLOW_SERVER_OVERRIDE) {
                item { SectionTitle("Сервер цен") }
                item {
                    OutlinedTextField(server, { server = it; model.updateSettings { s -> s.copy(serverUrl = it.trim()) } },
                                      placeholder = { Text("https://api.example.ru") }, singleLine = true,
                                      modifier = Modifier.fillMaxWidth().testTag("server-url"),
                                      supportingText = {
                                          Text(if (model.serverUrl == null) "Не указан — показываем тестовые цены"
                                               else "Цены с ${model.serverUrl}")
                                      })
                }
            }
            item {
                Text("ВыборВкуса ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE}) · Android",
                     fontSize = 12.sp, color = ant.textTertiary, modifier = Modifier.fillMaxWidth().padding(top = 16.dp),
                     textAlign = TextAlign.Center)
            }
        }
    }
}

// ---------- «Из того, что есть» ----------

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun FridgeScreen(loaded: AppModel.Loaded, nav: Nav) {
    val ant = Ant.colors
    val matcher = remember { FridgeMatcher(loaded.catalog) }
    var query by rememberSaveable { mutableStateOf("") }
    var selected by rememberSaveable { mutableStateOf(listOf<String>()) }
    val suggestions = remember(query) { matcher.categories(query) }.filter { it.first !in selected }
    val results = remember(selected) { matcher.match(loaded.catalog.recipes, selected.toSet()) }
    ScreenScaffold("Из того, что есть", onBack = { nav.back() }) { padding ->
        LazyColumn(Modifier.padding(padding).fillMaxSize(), contentPadding = PaddingValues(16.dp),
                   verticalArrangement = Arrangement.spacedBy(10.dp)) {
            item {
                OutlinedTextField(query, { query = it }, placeholder = { Text("Например: курица, рис, морковь") },
                                  singleLine = true, modifier = Modifier.fillMaxWidth())
            }
            if (selected.isNotEmpty()) {
                item {
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        selected.forEach { id ->
                            AntCheckableTag("${loaded.catalog.categoryTitle(id)} ✕", true, { selected = selected - id })
                        }
                    }
                }
            }
            item {
                Text(if (query.isBlank()) "Частые продукты" else "Подходит под «${query.trim()}»",
                     color = ant.textSecondary, fontSize = 13.sp)
            }
            item {
                FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    suggestions.take(if (query.isBlank()) 24 else 40).forEach { (id, title) ->
                        AntCheckableTag(title, false, { selected = selected + id; query = "" })
                    }
                }
            }
            item {
                SectionTitle(if (results.isEmpty()) "Рецепты" else "Можно приготовить: ${results.size}")
            }
            if (selected.isEmpty()) item { Text("Отметьте хотя бы один продукт. Соль, специи, масло и сахар считаем, что есть.",
                                                 color = ant.textTertiary) }
            items(results, key = { it.recipe.id }) { r ->
                PressCard({ nav.recipe(r.recipe.id) }, Modifier.fillMaxWidth()) {
                    Row(Modifier.padding(10.dp), verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.clip(RoundedCornerShape(AntSize.radius)).background(ant.rubric(r.recipe.rubric).bg).padding(6.dp)) {
                            FoodImage(r.recipe.icon, 40.dp)
                        }
                        Spacer(Modifier.width(12.dp))
                        Column(Modifier.weight(1f)) {
                            Text(r.recipe.title, fontWeight = FontWeight.SemiBold, color = ant.text)
                            if (r.isComplete) AntTag("Всё есть", ant.green)
                            else Text("Не хватает: " + r.missing.joinToString(", ") { it.title }, fontSize = 12.sp,
                                      color = ant.orange.text, maxLines = 2)
                        }
                        Text("${r.have.size}/${r.total}", fontSize = 12.sp, color = ant.textTertiary)
                    }
                }
            }
        }
    }
}

// ---------- Режим готовки ----------

/** Шаги по одному на экран, крупный текст, таймер из текста шага; экран не гаснет. */
@Composable
fun CookingScreen(loaded: AppModel.Loaded, nav: Nav, recipeId: String) {
    val recipe = loaded.catalog.recipe(recipeId) ?: return
    val ant = Ant.colors
    val context = LocalContext.current
    val pager = rememberPagerState { recipe.steps.size }
    val scope = rememberCoroutineScope()
    DisposableEffect(Unit) {
        val window = (context as? android.app.Activity)?.window
        window?.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        onDispose { window?.clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON) }
    }
    ScreenScaffold(recipe.title, onBack = { nav.back() }) { padding ->
        Column(Modifier.padding(padding).fillMaxSize()) {
            Text("Шаг ${pager.currentPage + 1} из ${recipe.steps.size}", color = ant.textSecondary,
                 modifier = Modifier.padding(horizontal = 16.dp))
            HorizontalPager(pager, Modifier.weight(1f).fillMaxWidth()) { page ->
                val step = recipe.steps[page]
                Column(Modifier.fillMaxSize().padding(24.dp), verticalArrangement = Arrangement.Center) {
                    Text(step, fontSize = 24.sp, lineHeight = 32.sp, color = ant.text)
                    StepTimer.duration(step)?.let { seconds ->
                        Spacer(Modifier.height(24.dp))
                        TimerCard(seconds)
                    }
                }
            }
            Row(Modifier.fillMaxWidth().padding(16.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedButton(onClick = { scope.launch { pager.animateScrollToPage(pager.currentPage - 1) } },
                               enabled = pager.currentPage > 0, modifier = Modifier.weight(1f)) { Text("Назад") }
                if (pager.currentPage < recipe.steps.size - 1) {
                    Button(onClick = { scope.launch { pager.animateScrollToPage(pager.currentPage + 1) } },
                           modifier = Modifier.weight(1f)) { Text("Дальше") }
                } else {
                    Button(onClick = { nav.back() }, modifier = Modifier.weight(1f)) { Text("Готово!") }
                }
            }
        }
    }
}

@Composable
private fun TimerCard(total: Long) {
    val ant = Ant.colors
    var left by remember(total) { mutableLongStateOf(total) }
    var running by remember(total) { mutableStateOf(false) }
    LaunchedEffect(running) {
        while (running && left > 0) {
            delay(1000)
            left -= 1
        }
        if (left == 0L) running = false
    }
    AntCard {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("⏱ ${StepTimer.format(left)}", fontSize = 28.sp, fontWeight = FontWeight.SemiBold,
                 color = if (left == 0L) ant.green.text else ant.text, modifier = Modifier.weight(1f))
            when {
                left == 0L -> OutlinedButton(onClick = { left = total }) { Text("Сначала") }
                running -> OutlinedButton(onClick = { running = false }) { Text("Пауза") }
                else -> Button(onClick = { running = true }) { Text("Старт") }
            }
        }
    }
}
