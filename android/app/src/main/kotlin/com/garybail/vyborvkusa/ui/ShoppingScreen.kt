package com.garybail.vyborvkusa.ui

import android.content.Intent
import android.view.WindowManager
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.garybail.vyborvkusa.AppModel
import com.garybail.vyborvkusa.core.ShoppingItem
import com.garybail.vyborvkusa.core.ShoppingList

/**
 * Общий список покупок: позиции из рецептов и сборок, сгруппированные по отделам магазина.
 * Режим «В магазине» — крупные строки, купленное уходит вниз, экран не гаснет.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun ShoppingScreen(model: AppModel, loaded: AppModel.Loaded) {
    val catalog = loaded.catalog
    val ant = Ant.colors
    val context = LocalContext.current
    val items = model.data.shopping
    val storeMode = model.data.settings.storeMode
    var confirmClear by remember { mutableStateOf(false) }

    // В магазине экран не должен гаснуть.
    DisposableEffect(storeMode) {
        val window = (context as? android.app.Activity)?.window
        if (storeMode) window?.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        onDispose { window?.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON) }
    }

    ScreenScaffold(
        title = "Покупки",
        actions = {
            if (items.isNotEmpty()) {
                IconButton(onClick = {
                    context.startActivity(Intent.createChooser(shareIntent(ShoppingList.shareText(items, catalog)), null))
                }) { Icon(Icons.Filled.Share, "Поделиться списком") }
                IconButton(onClick = { confirmClear = true }) { Icon(Icons.Filled.Delete, "Очистить") }
            }
        },
    ) { padding ->
        if (items.isEmpty()) {
            EmptyState("Список пуст", "Добавьте продукты со страницы рецепта или сборки — одинаковые сложатся.",
                       Modifier.padding(padding), icon = "shallow-pan-of-food")
        } else {
            ShoppingContent(model, loaded, items, storeMode, padding)
        }
    }

    if (confirmClear) {
        AlertDialog(
            onDismissRequest = { confirmClear = false },
            title = { Text("Очистить список?") },
            confirmButton = {
                TextButton(onClick = { model.clearShopping(); confirmClear = false }) { Text("Очистить", color = ant.error) }
            },
            dismissButton = { TextButton(onClick = { confirmClear = false }) { Text("Отмена") } },
        )
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun ShoppingContent(model: AppModel, loaded: AppModel.Loaded, items: List<ShoppingItem>, storeMode: Boolean,
                            padding: androidx.compose.foundation.layout.PaddingValues) {
        val catalog = loaded.catalog
        val ant = Ant.colors
        val done = items.count { it.isChecked }
        val visible = if (storeMode) items.sortedBy { it.isChecked } else items
        val groups = visible.groupBy { if (storeMode && it.isChecked) Int.MAX_VALUE else catalog.department(it.categoryId).first }
            .toSortedMap()
        LazyColumn(Modifier.padding(padding).fillMaxSize().testTag("shopping"),
                   contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp)) {
            item {
                Column(Modifier.padding(bottom = 8.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("Куплено $done из ${items.size}", color = ant.textSecondary, modifier = Modifier.weight(1f))
                        Text("В магазине", color = ant.text)
                        Spacer(Modifier.width(8.dp))
                        Switch(storeMode, { on -> model.updateSettings { it.copy(storeMode = on) } },
                               modifier = Modifier.testTag("store-mode"))
                    }
                    LinearProgressIndicator(progress = { done.toFloat() / items.size }, modifier = Modifier.fillMaxWidth(),
                                            color = ant.success, trackColor = ant.fill)
                }
            }
            for ((order, group) in groups) {
                stickyHeader(key = "h$order") {
                    Text(if (order == Int.MAX_VALUE) "Куплено" else catalog.department(group[0].categoryId).second,
                         fontWeight = FontWeight.SemiBold, color = ant.textSecondary, fontSize = 13.sp,
                         modifier = Modifier.fillMaxWidth().background(ant.bgLayout).padding(vertical = 8.dp))
                }
                items(group.sortedWith(compareBy(com.garybail.vyborvkusa.core.RU_COLLATOR) { it.title }), key = { it.id }) {
                    ShoppingRow(it, storeMode, onToggle = { model.toggleShopping(it.id) },
                                onRemove = { model.removeShopping(it.id) })
                }
            }
            if (done > 0) {
                item {
                    TextButton(onClick = { model.removeCheckedShopping() }) { Text("Убрать купленное") }
                }
            }
        }
}

@Composable
private fun ShoppingRow(item: ShoppingItem, storeMode: Boolean, onToggle: () -> Unit, onRemove: () -> Unit) {
    val ant = Ant.colors
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onToggle).background(ant.bgContainer)
            .padding(vertical = if (storeMode) 10.dp else 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Checkbox(item.isChecked, { onToggle() })
        Column(Modifier.weight(1f)) {
            Text(item.title, fontSize = if (storeMode) 19.sp else 16.sp,
                 color = if (item.isChecked) ant.textTertiary else ant.text,
                 textDecoration = if (item.isChecked) TextDecoration.LineThrough else null)
            if (item.sources.isNotEmpty() && !storeMode) {
                Text(item.sources.joinToString(", "), fontSize = 12.sp, color = ant.textTertiary)
            }
        }
        Text(item.amountText, fontSize = if (storeMode) 18.sp else 15.sp, color = ant.textSecondary)
        if (!storeMode) {
            IconButton(onClick = onRemove) { Icon(Icons.Filled.Delete, "Удалить", tint = ant.textTertiary) }
        } else {
            Spacer(Modifier.width(12.dp))
        }
    }
    Spacer(Modifier.height(1.dp))
}
