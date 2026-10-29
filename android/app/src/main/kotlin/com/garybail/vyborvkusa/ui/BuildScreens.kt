package com.garybail.vyborvkusa.ui

import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.ShoppingCart
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.garybail.vyborvkusa.AppModel
import com.garybail.vyborvkusa.core.DailyNorm
import com.garybail.vyborvkusa.core.ShoppingList
import kotlinx.coroutines.launch

/**
 * Выбор продуктов: для каждого ингредиента — конкретный товар из каталога.
 * По умолчанию выбран типичный продукт категории, чтобы сборку можно было сохранить сразу.
 */
@Composable
fun BuildEditorScreen(model: AppModel, loaded: AppModel.Loaded, nav: Nav, recipeId: String?, buildId: String?) {
    val catalog = loaded.catalog
    val existing = buildId?.let { id -> model.data.builds.firstOrNull { it.id == id } }
    val recipe = catalog.recipe(existing?.recipeId ?: recipeId.orEmpty()) ?: return
    val ant = Ant.colors
    var name by rememberSaveable { mutableStateOf(existing?.name ?: "Моя ${recipe.title.lowercase()}") }
    val selection = remember {
        mutableStateMapOf<String, String>().apply {
            for (ing in recipe.ingredients) {
                val chosen = existing?.selection?.get(ing.id)
                    ?: catalog.productsByCategory[ing.categoryId]?.firstOrNull()?.id
                if (chosen != null) put(ing.id, chosen)
            }
        }
    }
    var expanded by rememberSaveable { mutableStateOf<String?>(recipe.ingredients.firstOrNull()?.id) }
    // «Чаще выбирают»: что берут другие пользователи для этого рецепта (если сервер подключён).
    var choices by remember { mutableStateOf<com.garybail.vyborvkusa.core.Choices?>(null) }
    androidx.compose.runtime.LaunchedEffect(recipe.id) {
        choices = model.community()?.let { runCatching { it.choices(recipe.id) }.getOrNull() }
    }

    ScreenScaffold(
        title = if (existing == null) "Новая сборка" else "Изменить сборку",
        onBack = { nav.back() },
        bottomBar = {
            Box(Modifier.fillMaxWidth().background(ant.bgContainer).padding(12.dp)) {
                Button(
                    onClick = {
                        val id = model.saveBuild(existing?.id, name.trim().ifEmpty { recipe.title }, recipe.id,
                                                 selection.toMap())
                        if (existing == null) nav.build(id, replaceEditor = true) else nav.back()
                    },
                    modifier = Modifier.fillMaxWidth().testTag("save-build"),
                ) { Text("Сохранить сборку") }
            }
        },
    ) { padding ->
        LazyColumn(Modifier.padding(padding).fillMaxSize(), contentPadding = PaddingValues(16.dp),
                   verticalArrangement = Arrangement.spacedBy(10.dp)) {
            item {
                OutlinedTextField(name, { name = it }, label = { Text("Название") }, singleLine = true,
                                  modifier = Modifier.fillMaxWidth())
            }
            item {
                Text("Выберите продукт для каждого ингредиента — по ним посчитаем КБЖУ и сравним цены в магазинах.",
                     color = ant.textSecondary, fontSize = 14.sp)
            }
            val popular = choices
            if (popular != null && popular.builds > 0) {
                item {
                    OutlinedButton(onClick = {
                        for ((ingredientId, list) in popular.ingredients) {
                            val top = list.maxByOrNull { it.count } ?: continue
                            if (catalog.product(top.product.id) != null) selection[ingredientId] = top.product.id
                        }
                    }, modifier = Modifier.fillMaxWidth()) { Text("Выбрать как большинство (${popular.builds} сборок)") }
                }
            }
            items(recipe.ingredients, key = { it.id }) { ing ->
                val products = catalog.productsByCategory[ing.categoryId].orEmpty()
                val chosen = selection[ing.id]?.let(catalog::product)
                val open = expanded == ing.id
                AntCard {
                    Column {
                        Row(Modifier.fillMaxWidth().clickable { expanded = if (open) null else ing.id },
                            verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                Text("${ing.title} · ${recipe.amountText(ing, recipe.servings)}", color = ant.textSecondary,
                                     fontSize = 13.sp)
                                Text(chosen?.displayName ?: "Не выбрано", fontWeight = FontWeight.SemiBold,
                                     color = if (chosen == null) ant.textTertiary else ant.text)
                            }
                            Text(if (open) "Свернуть" else "${products.size} вар.", color = ant.primary, fontSize = 13.sp)
                        }
                        if (open) {
                            products.forEach { p ->
                                HorizontalDivider(color = ant.borderSecondary)
                                Row(Modifier.fillMaxWidth().clickable { selection[ing.id] = p.id }.padding(vertical = 4.dp),
                                    verticalAlignment = Alignment.CenterVertically) {
                                    RadioButton(selected = selection[ing.id] == p.id, onClick = { selection[ing.id] = p.id })
                                    Column(Modifier.weight(1f)) {
                                        Row(verticalAlignment = Alignment.CenterVertically) {
                                            Text(p.name, color = ant.text)
                                            val count = choices?.ingredients?.get(ing.id)?.firstOrNull { it.product.id == p.id }?.count
                                            if (count != null && count > 0) {
                                                Spacer(Modifier.width(6.dp))
                                                AntTag("чаще выбирают · $count", ant.volcano)
                                            }
                                        }
                                        val meta = listOfNotNull(p.brand, p.nutrition?.let { "${it.kcal.toInt()} ккал/100 г" })
                                        if (meta.isNotEmpty()) Text(meta.joinToString(" · "), fontSize = 12.sp, color = ant.textTertiary)
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

/** Сборка: выбранные продукты, порции, КБЖУ, сравнение цен, список покупок. */
@Composable
fun BuildScreen(model: AppModel, loaded: AppModel.Loaded, nav: Nav, id: String) {
    val catalog = loaded.catalog
    val build = model.data.builds.firstOrNull { it.id == id }
    if (build == null) {
        ScreenScaffold("Сборка", onBack = { nav.back() }) { p ->
            EmptyState("Сборка удалена", "Её больше нет на телефоне.", Modifier.padding(p))
        }
        return
    }
    val recipe = catalog.recipe(build.recipeId) ?: return
    val ant = Ant.colors
    val context = LocalContext.current
    val snackbar = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()
    var confirmDelete by remember { mutableStateOf(false) }
    val servings = build.effectiveServings(recipe)
    val nutrition = build.nutrition(catalog)

    ScreenScaffold(
        title = build.name,
        onBack = { nav.back() },
        actions = {
            IconButton(onClick = { nav.editBuild(id) }) { Icon(Icons.Filled.Edit, "Изменить продукты") }
            IconButton(onClick = {
                val text = buildString {
                    appendLine("🧺 ${build.name} — ${recipe.title}, $servings ${portionWord(servings)}")
                    ShoppingList.entries(build, catalog).forEach { appendLine("• ${it.title} — ${it.unit.format(it.amount)}") }
                    append("\nСобрано в приложении «ВыборВкуса»")
                }
                context.startActivity(Intent.createChooser(shareIntent(text), null))
            }) { Icon(Icons.Filled.Share, "Поделиться") }
            IconButton(onClick = { confirmDelete = true }) { Icon(Icons.Filled.Delete, "Удалить") }
        },
    ) { padding ->
        Box(Modifier.padding(padding)) {
            LazyColumn(Modifier.fillMaxSize().testTag("build"), contentPadding = PaddingValues(16.dp),
                       verticalArrangement = Arrangement.spacedBy(12.dp)) {
                item {
                    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(AntSize.radiusLG))
                            .background(ant.rubric(recipe.rubric).bg).clickable { nav.recipe(recipe.id) }.padding(12.dp),
                        verticalAlignment = Alignment.CenterVertically) {
                        FoodImage(recipe.icon, 48.dp)
                        Spacer(Modifier.width(12.dp))
                        Column(Modifier.weight(1f)) {
                            Text(recipe.title, fontWeight = FontWeight.SemiBold, color = ant.text)
                            Text("Открыть рецепт", fontSize = 13.sp, color = ant.primary)
                        }
                    }
                }
                item {
                    Button(onClick = { nav.compare(id) }, modifier = Modifier.fillMaxWidth().testTag("compare")) {
                        Text("Сравнить цены в магазинах")
                    }
                }
                item { PriceWatchCard(model, nav, id, build.isWatched) }
                item { PublishCard(model, nav, build) }
                item {
                    SectionTitle("Продукты") { ServingsStepper(servings, { model.setBuildServings(id, it) }) }
                }
                item {
                    AntCard {
                        Column {
                            recipe.ingredients.forEachIndexed { i, ing ->
                                if (i > 0) HorizontalDivider(color = ant.borderSecondary)
                                val product = build.product(ing, catalog)
                                Row(Modifier.fillMaxWidth().padding(vertical = 8.dp)) {
                                    Column(Modifier.weight(1f)) {
                                        Text(product?.displayName ?: ing.title, color = ant.text)
                                        if (product != null) Text(ing.title, fontSize = 12.sp, color = ant.textTertiary)
                                    }
                                    Text(recipe.amountText(ing, servings), color = ant.textSecondary)
                                }
                            }
                        }
                    }
                }
                item {
                    OutlinedButton(onClick = {
                        model.addToShopping(ShoppingList.entries(build, catalog))
                        scope.launch { snackbar.showSnackbar("Добавлено в список покупок") }
                    }, modifier = Modifier.fillMaxWidth()) {
                        Icon(Icons.Filled.ShoppingCart, null, Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("В список покупок")
                    }
                }
                if (nutrition.grams > 0) {
                    item { SectionTitle("КБЖУ порции") }
                    item { NutritionCard(nutrition.perServing(recipe.servings), DailyNorm(model.data.settings.dailyKcal.toDouble())) }
                    if (nutrition.missing.isNotEmpty()) {
                        item {
                            Text("Без данных: ${nutrition.missing.joinToString(", ")}", fontSize = 12.sp,
                                 color = ant.textTertiary)
                        }
                    }
                }
            }
            SnackbarHost(snackbar, Modifier.align(Alignment.BottomCenter))
        }
    }

    if (confirmDelete) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text("Удалить сборку?") },
            text = { Text("«${build.name}» пропадёт с телефона.") },
            confirmButton = {
                TextButton(onClick = { confirmDelete = false; nav.back(); model.deleteBuild(id) }) {
                    Text("Удалить", color = ant.error)
                }
            },
            dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text("Отмена") } },
        )
    }
}

/** Публикация сборки в сообществе (вместе со своим рецептом). */
@Composable
private fun PublishCard(model: AppModel, nav: Nav, build: com.garybail.vyborvkusa.core.Build) {
    val ant = Ant.colors
    val scope = rememberCoroutineScope()
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val account = model.account
    AntCard {
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text("Сообщество", fontWeight = FontWeight.SemiBold, color = ant.text)
            when {
                build.authorName != null -> Text("Сборка ${build.authorName} из сообщества.", fontSize = 13.sp, color = ant.textSecondary)
                account == null -> {
                    Text("Поделитесь сборкой — другие увидят ваш выбор продуктов и смогут оценить.", fontSize = 13.sp,
                         color = ant.textSecondary)
                    OutlinedButton(onClick = { nav.auth() }) { Text("Войти, чтобы опубликовать") }
                }
                !account.isEmailVerified -> Text("Подтвердите почту в профиле, чтобы публиковать сборки.", fontSize = 13.sp,
                                                  color = ant.textSecondary)
                build.remoteId != null -> {
                    AntTag("Опубликовано", ant.green)
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedButton(onClick = { nav.communityBuild(build.remoteId!!) }) { Text("Открыть") }
                        TextButton(onClick = {
                            busy = true
                            scope.launch { error = model.unpublish(build.id); busy = false }
                        }, enabled = !busy) { Text("Снять с публикации") }
                    }
                }
                else -> Button(onClick = {
                    busy = true
                    scope.launch { error = model.publish(build.id); busy = false }
                }, enabled = !busy, modifier = Modifier.testTag("publish")) { Text("Опубликовать в сообществе") }
            }
            error?.let { Text(it, color = ant.error, fontSize = 13.sp) }
        }
    }
}
