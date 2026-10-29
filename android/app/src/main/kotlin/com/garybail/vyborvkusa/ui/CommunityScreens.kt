package com.garybail.vyborvkusa.ui

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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.garybail.vyborvkusa.AppModel
import com.garybail.vyborvkusa.core.AppNotification
import com.garybail.vyborvkusa.core.CommunityApi
import com.garybail.vyborvkusa.core.CommunityBuild
import com.garybail.vyborvkusa.core.CommunityRating
import com.garybail.vyborvkusa.core.CommunityRecipeEntry
import com.garybail.vyborvkusa.core.MeasureUnit
import kotlinx.coroutines.launch

/** Звёзды рейтинга: «★★★★☆ 4,3 · 12». */
fun stars(avg: Double?, count: Int): String {
    if (avg == null || count == 0) return "Пока без оценок"
    val full = kotlin.math.round(avg).toInt().coerceIn(0, 5)
    return "★".repeat(full) + "☆".repeat(5 - full) + " " + String.format(java.util.Locale("ru"), "%.1f", avg) + " · $count"
}

/** Колокольчик с числом непрочитанных уведомлений. */
@Composable
fun NotificationsBell(model: AppModel, nav: Nav) {
    if (model.account == null) return
    LaunchedEffect(Unit) { model.notifications() }
    IconButton(onClick = { nav.notifications() }, modifier = Modifier.testTag("bell")) {
        if (model.unreadCount > 0) {
            BadgedBox(badge = { Badge { Text("${model.unreadCount}") } }) { Icon(Icons.Filled.Notifications, "Уведомления") }
        } else {
            Icon(Icons.Filled.Notifications, "Уведомления")
        }
    }
}

// ---------- Лента ----------

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CommunityScreen(model: AppModel, loaded: AppModel.Loaded, nav: Nav) {
    val ant = Ant.colors
    val client = remember(model.serverUrl, model.account) { model.community() }
    var tab by rememberSaveable { mutableStateOf(0) }
    var sort by rememberSaveable { mutableStateOf(CommunityApi.Sort.TOP) }
    var builds by remember { mutableStateOf<List<CommunityBuild>?>(null) }
    var recipes by remember { mutableStateOf<List<CommunityRecipeEntry>?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var attempt by remember { mutableStateOf(0) }

    LaunchedEffect(client, tab, sort, attempt) {
        if (client == null) return@LaunchedEffect
        error = null
        try {
            if (tab == 0) builds = client.builds(sort) else recipes = client.recipes(sort)
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: Exception) {
            error = e.message ?: "Нет связи с сервером"
        }
    }

    ScreenScaffold("Сообщество", actions = {
        IconButton(onClick = { attempt++ }) { Icon(Icons.Filled.Refresh, "Обновить") }
        NotificationsBell(model, nav)
    }) { padding ->
        if (client == null) {
            EmptyState("Сообщество недоступно", "Укажите адрес сервера в профиле — здесь появятся сборки и рецепты других людей.",
                       Modifier.padding(padding), icon = "cooking")
        } else LazyColumn(Modifier.padding(padding).fillMaxSize().testTag("community"), contentPadding = PaddingValues(16.dp),
                   verticalArrangement = Arrangement.spacedBy(10.dp)) {
            item {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                        listOf("Сборки", "Рецепты").forEachIndexed { i, title ->
                            SegmentedButton(selected = tab == i, onClick = { tab = i },
                                            shape = SegmentedButtonDefaults.itemShape(i, 2)) { Text(title) }
                        }
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        CommunityApi.Sort.entries.forEach { s -> AntCheckableTag(s.title, sort == s, { sort = s }) }
                    }
                }
            }
            error?.let { item { Text(it, color = ant.error) } }
            if (tab == 0) {
                val list = builds
                when {
                    list == null && error == null -> item { Loading() }
                    list != null && list.isEmpty() -> item { Text("Пока никто не поделился сборкой — будьте первым!", color = ant.textSecondary) }
                    list != null -> items(list, key = { it.id }) { b -> CommunityBuildCard(b, loaded) { nav.communityBuild(b.id) } }
                }
            } else {
                val list = recipes
                when {
                    list == null && error == null -> item { Loading() }
                    list != null && list.isEmpty() -> item { Text("Своих рецептов в сообществе пока нет.", color = ant.textSecondary) }
                    list != null -> items(list, key = { it.recipe.id }) { r ->
                        PressCard({ nav.communityBuild(r.bestBuildId) }, Modifier.fillMaxWidth()) {
                            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                Text(r.recipe.title, fontWeight = FontWeight.SemiBold, color = ant.text)
                                Text("${r.authorName} · сборок: ${r.buildsCount}", fontSize = 13.sp, color = ant.textSecondary)
                                Text(stars(r.ratingAvg, r.ratingCount), fontSize = 13.sp, color = ant.gold.text)
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun Loading() {
    Box(Modifier.fillMaxWidth().padding(32.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
}

@Composable
private fun CommunityBuildCard(b: CommunityBuild, loaded: AppModel.Loaded, onClick: () -> Unit) {
    val ant = Ant.colors
    val icon = loaded.catalog.recipe(b.recipe.id)?.icon ?: "shallow-pan-of-food"
    PressCard(onClick, Modifier.fillMaxWidth().testTag("community-build")) {
        Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
            FoodImage(icon, 44.dp)
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(b.name, fontWeight = FontWeight.SemiBold, color = ant.text)
                Text("${b.recipe.title} · ${b.authorName}", fontSize = 13.sp, color = ant.textSecondary)
                Text(stars(b.ratingAvg, b.ratingCount), fontSize = 13.sp, color = ant.gold.text)
            }
        }
    }
}

// ---------- Сборка из сообщества ----------

@Composable
fun CommunityBuildScreen(model: AppModel, loaded: AppModel.Loaded, nav: Nav, id: String) {
    val ant = Ant.colors
    val scope = rememberCoroutineScope()
    val snackbar = remember { SnackbarHostState() }
    val client = remember(model.serverUrl, model.account) { model.community() }
    var build by remember { mutableStateOf<CommunityBuild?>(null) }
    var ratings by remember { mutableStateOf<List<CommunityRating>>(emptyList()) }
    var error by remember { mutableStateOf<String?>(null) }
    var rating by remember { mutableStateOf(false) }
    var menu by remember { mutableStateOf(false) }

    LaunchedEffect(client, id) {
        if (client == null) return@LaunchedEffect
        try {
            build = client.build(id)
            ratings = runCatching { client.ratings(id) }.getOrDefault(emptyList())
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: Exception) {
            error = e.message ?: "Не удалось загрузить сборку"
        }
    }
    val b = build
    val mine = b != null && model.account?.id == b.authorId

    ScreenScaffold(b?.name ?: "Сборка", onBack = { nav.back() }, actions = {
        if (b != null && model.account != null && !mine) {
            Box {
                IconButton(onClick = { menu = true }) { Icon(Icons.Filled.MoreVert, "Ещё") }
                DropdownMenu(menu, { menu = false }) {
                    DropdownMenuItem(text = { Text("Пожаловаться") }, onClick = {
                        menu = false
                        scope.launch {
                            val r = runCatching { client?.report(b.id, "Неуместное содержание") }
                            snackbar.showSnackbar(if (r.isSuccess) "Спасибо, проверим" else r.exceptionOrNull()?.message ?: "Ошибка")
                        }
                    })
                    DropdownMenuItem(text = { Text("Скрыть автора") }, onClick = {
                        menu = false
                        scope.launch {
                            runCatching { client?.block(b.authorId) }
                            nav.back()
                        }
                    })
                }
            }
        }
    }) { padding ->
        Box(Modifier.padding(padding).fillMaxSize()) {
            when {
                error != null -> EmptyState("Не получилось", error.orEmpty())
                b == null -> Loading()
                else -> LazyColumn(Modifier.fillMaxSize().testTag("community-build-detail"), contentPadding = PaddingValues(16.dp),
                                   verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    item {
                        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text(b.recipe.title, fontSize = 22.sp, fontWeight = FontWeight.Bold, color = ant.text)
                            Text("Автор: ${b.authorName}", color = ant.textSecondary)
                            Text(stars(b.ratingAvg, b.ratingCount), color = ant.gold.text)
                        }
                    }
                    item {
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Button(onClick = { nav.build(model.saveCommunityBuild(b)) }, modifier = Modifier.weight(1f).testTag("save-community")) {
                                Text("Сохранить себе")
                            }
                            if (!mine) {
                                OutlinedButton(onClick = {
                                    if (model.account == null) nav.auth() else rating = true
                                }, modifier = Modifier.weight(1f)) { Text(if (b.myRating != null) "Моя оценка: ${b.myRating}" else "Оценить") }
                            }
                        }
                    }
                    item { SectionTitle("Продукты · ${b.recipe.servings} ${portionWord(b.recipe.servings)}") }
                    item {
                        AntCard {
                            Column {
                                b.recipe.ingredients.forEachIndexed { i, ing ->
                                    if (i > 0) HorizontalDivider(color = ant.borderSecondary)
                                    val p = b.product(ing.id)
                                    Row(Modifier.fillMaxWidth().padding(vertical = 8.dp)) {
                                        Column(Modifier.weight(1f)) {
                                            Text(p?.displayName ?: ing.title, color = ant.text)
                                            if (p != null) Text(ing.title, fontSize = 12.sp, color = ant.textTertiary)
                                        }
                                        Text(MeasureUnit.fromRaw(ing.unit).format(ing.amount), color = ant.textSecondary)
                                    }
                                }
                            }
                        }
                    }
                    if (b.recipe.steps.isNotEmpty() && b.recipe.id.startsWith("user-")) {
                        item { SectionTitle("Приготовление") }
                        b.recipe.steps.forEachIndexed { i, s -> item { StepRow(i + 1, s) } }
                    } else if (loaded.catalog.recipe(b.recipe.id) != null) {
                        item { TextButton(onClick = { nav.recipe(b.recipe.id) }) { Text("Открыть рецепт") } }
                    }
                    if (ratings.isNotEmpty()) {
                        item { SectionTitle("Отзывы") }
                        items(ratings) { r ->
                            AntCard {
                                Column {
                                    Text("${"★".repeat(r.stars)} ${r.authorName}", color = ant.text, fontWeight = FontWeight.Medium)
                                    r.comment?.let { Text(it, color = ant.textSecondary) }
                                }
                            }
                        }
                    }
                }
            }
            SnackbarHost(snackbar, Modifier.align(Alignment.BottomCenter))
        }
    }

    if (rating && b != null) {
        RatingDialog(b.myRating ?: 5, onDismiss = { rating = false }) { starsValue, comment ->
            scope.launch {
                val result = runCatching { client!!.rate(b.id, starsValue, comment) }
                result.onSuccess {
                    build = it
                    ratings = runCatching { client!!.ratings(b.id) }.getOrDefault(ratings)
                    rating = false
                }
                result.onFailure { snackbar.showSnackbar(it.message ?: "Не удалось оценить"); rating = false }
            }
        }
    }
}

@Composable
private fun RatingDialog(initial: Int, onDismiss: () -> Unit, onSubmit: (Int, String?) -> Unit) {
    var value by remember { mutableStateOf(initial) }
    var comment by remember { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Ваша оценка") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row {
                    (1..5).forEach { n ->
                        Text(if (n <= value) "★" else "☆", fontSize = 34.sp, color = Ant.colors.gold.base,
                             modifier = Modifier.clickable { value = n }.padding(4.dp))
                    }
                }
                OutlinedTextField(comment, { comment = it.take(500) }, label = { Text("Отзыв (необязательно)") },
                                  modifier = Modifier.fillMaxWidth())
            }
        },
        confirmButton = { TextButton(onClick = { onSubmit(value, comment) }) { Text("Отправить") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Отмена") } },
    )
}

// ---------- Уведомления ----------

@Composable
fun NotificationsScreen(model: AppModel, nav: Nav) {
    val ant = Ant.colors
    var items by remember { mutableStateOf<List<AppNotification>?>(null) }
    LaunchedEffect(Unit) {
        val list = model.notifications()
        items = list?.items.orEmpty()
        list?.items?.filter { !it.isRead }?.map { it.id }?.let { model.markNotificationsRead(it) }
    }
    ScreenScaffold("Уведомления", onBack = { nav.back() }) { padding ->
        val list = items
        when {
            list == null -> Box(Modifier.padding(padding)) { Loading() }
            list.isEmpty() -> EmptyState("Пока тихо", "Здесь появятся оценки ваших сборок и новости о ценах.",
                                         Modifier.padding(padding), icon = "cooking")
            else -> LazyColumn(Modifier.padding(padding).fillMaxSize(), contentPadding = PaddingValues(16.dp),
                               verticalArrangement = Arrangement.spacedBy(8.dp)) {
                items(list, key = { it.id }) { n ->
                    AntCard(Modifier.clickable {
                        val target = n.buildId ?: return@clickable
                        if (n.isAboutPrice) {
                            if (model.data.builds.any { it.id == target }) nav.build(target)
                        } else nav.communityBuild(target)
                    }) {
                        Column {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(n.title, fontWeight = FontWeight.SemiBold, color = ant.text, modifier = Modifier.weight(1f))
                                if (!n.isRead) AntTag("новое", ant.blue)
                            }
                            Text(n.body, color = ant.textSecondary, fontSize = 14.sp)
                        }
                    }
                }
            }
        }
    }
    Spacer(Modifier.height(0.dp))
}
