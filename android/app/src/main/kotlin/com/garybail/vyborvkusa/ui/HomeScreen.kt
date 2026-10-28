package com.garybail.vyborvkusa.ui

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.garybail.vyborvkusa.AppModel
import com.garybail.vyborvkusa.core.Recipe
import com.garybail.vyborvkusa.core.RecipeCollection
import com.garybail.vyborvkusa.core.RecipeFilter

/** Главная: поиск, подборки, кухни, рубрики, фильтры и сетка рецептов. */
@Composable
fun HomeScreen(model: AppModel, loaded: AppModel.Loaded, nav: Nav) {
    val catalog = loaded.catalog
    val ant = Ant.colors
    var query by rememberSaveable { mutableStateOf("") }
    var rubric by rememberSaveable { mutableStateOf<String?>(null) }
    var cuisine by rememberSaveable { mutableStateOf<String?>(null) }
    var filterNames by rememberSaveable { mutableStateOf(listOf<String>()) }
    val filters = filterNames.mapNotNull { n -> RecipeFilter.entries.firstOrNull { it.name == n } }
    val profile = model.data.settings.diet

    val recipes = remember(query, rubric, cuisine, filterNames, profile) {
        val q = query.trim().lowercase()
        catalog.recipes.filter { r ->
            (rubric == null || r.rubric == rubric) &&
                (cuisine == null || r.cuisine == cuisine) &&
                (q.isEmpty() || q in r.title.lowercase() ||
                    r.ingredients.any { q in it.title.lowercase() }) &&
                filters.all { it.matches(r, loaded.kcal[r.id], profile, loaded.traits) }
        }
    }
    val browsing = query.isBlank() && rubric == null && cuisine == null && filters.isEmpty()

    LazyVerticalGrid(
        columns = GridCells.Fixed(2),
        modifier = Modifier.fillMaxSize().background(ant.bgLayout).testTag("home"),
        contentPadding = PaddingValues(16.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item(span = { GridItemSpan(2) }) { Hero(catalog.recipes.size, catalog.products.size) }
        item(span = { GridItemSpan(2) }) {
            OutlinedTextField(
                value = query, onValueChange = { query = it },
                modifier = Modifier.fillMaxWidth().testTag("search"),
                placeholder = { Text("Рецепт или продукт") },
                leadingIcon = { Icon(Icons.Filled.Search, null) },
                trailingIcon = {
                    if (query.isNotEmpty()) IconButton(onClick = { query = "" }) { Icon(Icons.Filled.Clear, "Очистить") }
                },
                singleLine = true,
                shape = RoundedCornerShape(AntSize.radiusLG),
                colors = OutlinedTextFieldDefaults.colors(focusedContainerColor = ant.bgContainer,
                                                          unfocusedContainerColor = ant.bgContainer,
                                                          unfocusedBorderColor = ant.border),
            )
        }
        if (browsing) {
            item(span = { GridItemSpan(2) }) { FridgeLink { nav.fridge() } }
            item(span = { GridItemSpan(2) }) {
                Column {
                    SectionTitle("Подборки")
                    LazyRow(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        items(RecipeCollection.all()) { c ->
                            CollectionCard(c, c.recipes(catalog.recipes, loaded.traits).size) { nav.collection(c.id) }
                        }
                    }
                }
            }
        }
        item(span = { GridItemSpan(2) }) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                SectionTitle("Кухни мира")
                LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(catalog.cuisines) { c ->
                        AntCheckableTag(c.title, cuisine == c.id, { cuisine = if (cuisine == c.id) null else c.id })
                    }
                }
                LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    item { AntCheckableTag("Все", rubric == null, { rubric = null }) }
                    items(catalog.rubrics) { r ->
                        AntCheckableTag(r.title, rubric == r.id, { rubric = if (rubric == r.id) null else r.id })
                    }
                }
                LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(RecipeFilter.entries) { f ->
                        val on = f.name in filterNames
                        AntCheckableTag(f.title, on, {
                            filterNames = if (on) filterNames - f.name else filterNames + f.name
                        }, Modifier.testTag("filter-${f.name.lowercase()}"))
                    }
                }
                if (RecipeFilter.SAFE in filters && profile.isEmpty) {
                    Text("Укажите аллергии и ограничения в профиле — фильтр «Мне подходит» учтёт их.",
                         color = ant.textSecondary, fontSize = 13.sp)
                }
                Text(if (browsing) "Все рецепты · ${recipes.size}" else "Найдено: ${recipes.size}",
                     style = MaterialTheme.typography.titleMedium, color = ant.text,
                     modifier = Modifier.padding(top = 8.dp))
            }
        }
        items(recipes, key = { it.id }) { r ->
            RecipeCard(r, loaded.kcal[r.id], { nav.recipe(r.id) }, rubricTitle = catalog.rubric(r.rubric)?.title)
        }
        if (recipes.isEmpty()) {
            item(span = { GridItemSpan(2) }) {
                EmptyState("Ничего не нашлось", "Попробуйте другое слово или уберите фильтры.", icon = "cooking",
                           modifier = Modifier.height(260.dp))
            }
        }
    }
}

/** Шапка с мягко переливающимся фоном (как AuroraBackground в iOS) и счётчиками каталога. */
@Composable
private fun Hero(recipes: Int, products: Int) {
    val ant = Ant.colors
    val shift by rememberInfiniteTransition(label = "aurora").animateFloat(
        0f, 1f, infiniteRepeatable(tween(9000, easing = LinearEasing), RepeatMode.Reverse), label = "shift")
    val brush = Brush.linearGradient(
        listOf(ant.blue.bg, ant.purple.bg, ant.volcano.bg),
        start = androidx.compose.ui.geometry.Offset(shift * 600f, 0f),
        end = androidx.compose.ui.geometry.Offset(600f + shift * 400f, 500f),
    )
    Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(AntSize.radiusLG)).background(brush).padding(18.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("ВыборВкуса", fontSize = 28.sp, fontWeight = FontWeight.Bold, color = ant.text)
                Text("Ваши любимые рецепты и продукты в одной корзине", color = ant.textSecondary, fontSize = 14.sp)
                Spacer(Modifier.height(10.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    Counter(recipes, "рецептов")
                    Counter(products, "продуктов")
                }
            }
            FoodImage("cooking", 72.dp)
        }
    }
}

@Composable
private fun Counter(value: Int, label: String) {
    Column {
        Text("$value", fontSize = 20.sp, fontWeight = FontWeight.SemiBold, color = Ant.colors.primary)
        Text(label, fontSize = 12.sp, color = Ant.colors.textTertiary)
    }
}

@Composable
private fun FridgeLink(onClick: () -> Unit) {
    val ant = Ant.colors
    PressCard(onClick, Modifier.fillMaxWidth().testTag("fridge-link")) {
        Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
            FoodImage("leafy-green", 40.dp)
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text("Что приготовить из того, что есть?", fontWeight = FontWeight.SemiBold, color = ant.text)
                Text("Отметьте продукты — подберём рецепты", fontSize = 13.sp, color = ant.textSecondary)
            }
        }
    }
}

@Composable
fun CollectionCard(collection: RecipeCollection, count: Int, onClick: () -> Unit) {
    val palette = Ant.colors.named(collection.palette)
    Column(
        Modifier.width(150.dp).height(130.dp)
            .clip(RoundedCornerShape(AntSize.radiusLG))
            .background(palette.bg)
            .border(1.dp, palette.border, RoundedCornerShape(AntSize.radiusLG))
            .clickable(onClick = onClick)
            .padding(12.dp)
            .testTag("collection-${collection.id}"),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            FoodImage(collection.icon, 40.dp)
            Spacer(Modifier.weight(1f))
            Text("$count", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = palette.text,
                 modifier = Modifier.clip(RoundedCornerShape(50)).background(Color.White.copy(alpha = 0.7f))
                     .padding(horizontal = 7.dp, vertical = 2.dp))
        }
        Spacer(Modifier.weight(1f))
        Text(collection.title, fontWeight = FontWeight.SemiBold, color = Ant.colors.text, fontSize = 14.sp)
        Text(collection.subtitle, fontSize = 12.sp, color = Ant.colors.textSecondary, maxLines = 2)
    }
}

/** Сетка рецептов для подборок и избранного. */
@Composable
fun RecipeGrid(recipes: List<Recipe>, loaded: AppModel.Loaded, nav: Nav, modifier: Modifier = Modifier,
               header: (@Composable () -> Unit)? = null) {
    LazyVerticalGrid(
        columns = GridCells.Fixed(2),
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (header != null) item(span = { GridItemSpan(2) }) { header() }
        items(recipes, key = { it.id }) { r ->
            RecipeCard(r, loaded.kcal[r.id], { nav.recipe(r.id) },
                       rubricTitle = loaded.catalog.rubric(r.rubric)?.title)
        }
    }
}

@Composable
fun CollectionScreen(loaded: AppModel.Loaded, nav: Nav, id: String) {
    val collection = RecipeCollection.all().firstOrNull { it.id == id } ?: return
    val recipes = remember(id) { collection.recipes(loaded.catalog.recipes, loaded.traits) }
    ScreenScaffold(collection.title, onBack = { nav.back() }) { padding ->
        RecipeGrid(recipes, loaded, nav, Modifier.padding(padding)) {
            Text(collection.subtitle, color = Ant.colors.textSecondary)
        }
    }
}
