package com.garybail.vyborvkusa.ui

import android.content.Intent
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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.ShoppingCart
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.garybail.vyborvkusa.AppModel
import com.garybail.vyborvkusa.core.DailyNorm
import com.garybail.vyborvkusa.core.Nutrition
import com.garybail.vyborvkusa.core.Recipe
import com.garybail.vyborvkusa.core.ShoppingList
import com.garybail.vyborvkusa.core.StepTimer
import kotlinx.coroutines.launch

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun RecipeScreen(model: AppModel, loaded: AppModel.Loaded, nav: Nav, id: String) {
    val catalog = loaded.catalog
    val recipe = catalog.recipe(id) ?: return
    val ant = Ant.colors
    val context = LocalContext.current
    val snackbar = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()
    val data = model.data
    val servings = data.recipeServings[id] ?: recipe.servings
    val favorite = data.isFavorite(id)
    val summary = remember(id) { loaded.nutrition.summary(recipe) }
    val warnings = data.settings.diet.warnings(recipe, loaded.traits)
    val builds = data.builds.filter { it.recipeId == id }
    val palette = ant.rubric(recipe.rubric)

    ScreenScaffold(
        title = recipe.title,
        onBack = { nav.back() },
        actions = {
            IconButton(onClick = { model.toggleFavorite(id) }, modifier = Modifier.testTag("favorite")) {
                Icon(if (favorite) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder,
                     if (favorite) "Убрать из избранного" else "В избранное",
                     tint = if (favorite) ant.red.base else ant.text)
            }
            IconButton(onClick = { context.startActivity(Intent.createChooser(shareIntent(recipeText(recipe, servings, loaded)), null)) }) {
                Icon(Icons.Filled.Share, "Поделиться")
            }
        },
    ) { padding ->
        Box(Modifier.padding(padding)) {
            LazyColumn(
                Modifier.fillMaxSize().testTag("recipe"),
                contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                item {
                    Box(Modifier.fillMaxWidth().height(170.dp).clip(RoundedCornerShape(AntSize.radiusLG))
                            .background(palette.bg), contentAlignment = Alignment.Center) {
                        FoodImage(recipe.icon, 110.dp)
                    }
                }
                item {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(recipe.title, fontSize = 26.sp, fontWeight = FontWeight.Bold, color = ant.text)
                        if (recipe.summary.isNotBlank()) Text(recipe.summary, color = ant.textSecondary)
                        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            catalog.rubric(recipe.rubric)?.let { AntTag(it.title, palette) }
                            catalog.cuisine(recipe.cuisine)?.let { AntTag(it.title, ant.geekblue) }
                            if (recipe.cookMinutes > 0) AntTag("${recipe.cookMinutes} мин", ant.cyan)
                            loaded.kcal[id]?.let { AntTag("${it.toInt()} ккал/порция", ant.orange) }
                            if (loaded.traits.isLenten(recipe)) AntTag("Постное", ant.green)
                            else if (loaded.traits.isVegetarian(recipe)) AntTag("Без мяса", ant.green)
                        }
                    }
                }
                if (warnings.isNotEmpty()) {
                    item {
                        Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(AntSize.radiusLG)).background(ant.gold.bg)
                                .padding(12.dp)) {
                            Icon(Icons.Filled.Warning, null, tint = ant.gold.text)
                            Spacer(Modifier.width(8.dp))
                            Column {
                                Text("Не подходит по вашему профилю", fontWeight = FontWeight.SemiBold, color = ant.gold.text)
                                warnings.forEach { Text(it, color = ant.text, fontSize = 14.sp) }
                            }
                        }
                    }
                }
                item {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(onClick = { nav.newBuild(id) }, modifier = Modifier.weight(1f).testTag("make-build")) {
                            Text("Выбрать продукты")
                        }
                        OutlinedButton(onClick = { nav.cooking(id) }, modifier = Modifier.weight(1f)) {
                            Icon(Icons.Filled.PlayArrow, null, Modifier.size(18.dp))
                            Spacer(Modifier.width(4.dp))
                            Text("Готовить")
                        }
                    }
                }
                if (builds.isNotEmpty()) {
                    item { SectionTitle("Мои сборки") }
                    items(builds, key = { it.id }) { b ->
                        AntCard(Modifier.clickable { nav.build(b.id) }) {
                            Column {
                                Text(b.name, fontWeight = FontWeight.SemiBold, color = ant.text)
                                Text("${b.selection.size} из ${recipe.ingredients.size} продуктов выбрано",
                                     fontSize = 13.sp, color = ant.textSecondary)
                            }
                        }
                    }
                }
                item {
                    SectionTitle("Ингредиенты") {
                        ServingsStepper(servings, { model.setRecipeServings(id, it) })
                    }
                }
                item {
                    AntCard {
                        Column {
                            recipe.ingredients.forEachIndexed { i, ing ->
                                if (i > 0) HorizontalDivider(color = ant.borderSecondary)
                                Row(Modifier.fillMaxWidth().padding(vertical = 8.dp)) {
                                    Text(ing.title, color = ant.text, modifier = Modifier.weight(1f))
                                    Text(recipe.amountText(ing, servings), color = ant.textSecondary)
                                }
                            }
                        }
                    }
                }
                item {
                    OutlinedButton(onClick = {
                        model.addToShopping(ShoppingList.entries(recipe, servings))
                        scope.launch { snackbar.showSnackbar("Добавлено в список покупок") }
                    }, modifier = Modifier.fillMaxWidth().testTag("add-to-shopping")) {
                        Icon(Icons.Filled.ShoppingCart, null, Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("В список покупок")
                    }
                }
                if (summary.grams > 0) {
                    item { SectionTitle("КБЖУ порции") }
                    item { NutritionCard(summary.perServing(recipe.servings), DailyNorm(data.settings.dailyKcal.toDouble())) }
                }
                item { SectionTitle("Приготовление") }
                itemsIndexed(recipe.steps) { i, step -> StepRow(i + 1, step) }
            }
            SnackbarHost(snackbar, Modifier.align(Alignment.BottomCenter))
        }
    }
}

@Composable
fun StepRow(number: Int, text: String) {
    val ant = Ant.colors
    Row(Modifier.fillMaxWidth()) {
        Box(Modifier.size(28.dp).clip(CircleShape).background(ant.primary), contentAlignment = Alignment.Center) {
            Text("$number", color = Color.White, fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
        }
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(text, color = ant.text)
            StepTimer.duration(text)?.let {
                Spacer(Modifier.height(4.dp))
                AntTag("⏱ ${StepTimer.format(it)}", ant.cyan)
            }
        }
    }
}

@Composable
fun NutritionCard(n: Nutrition, norm: DailyNorm) {
    val ant = Ant.colors
    val p = norm.percent(n)
    AntCard {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            NutritionCell("${n.kcal.toInt()}", "ккал", p.kcal, ant.orange)
            NutritionCell("${n.protein.toInt()} г", "белки", p.protein, ant.blue)
            NutritionCell("${n.fat.toInt()} г", "жиры", p.fat, ant.gold)
            NutritionCell("${n.carbs.toInt()} г", "углеводы", p.carbs, ant.green)
        }
    }
}

@Composable
private fun NutritionCell(value: String, label: String, percent: Int, palette: Palette) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(value, fontWeight = FontWeight.SemiBold, color = Ant.colors.text)
        Text(label, fontSize = 12.sp, color = Ant.colors.textTertiary)
        Spacer(Modifier.height(4.dp))
        AntTag("$percent%", palette)
    }
}

fun shareIntent(text: String): Intent = Intent(Intent.ACTION_SEND).apply {
    type = "text/plain"
    putExtra(Intent.EXTRA_TEXT, text)
}

fun recipeText(recipe: Recipe, servings: Int, loaded: AppModel.Loaded): String = buildString {
    appendLine("🍽 ${recipe.title} — ${servings} ${portionWord(servings)}")
    appendLine()
    recipe.ingredients.forEach { appendLine("• ${it.title} — ${recipe.amountText(it, servings)}") }
    appendLine()
    recipe.steps.forEachIndexed { i, s -> appendLine("${i + 1}. $s") }
    loaded.kcal[recipe.id]?.let { appendLine(); appendLine("≈ ${it.toInt()} ккал на порцию") }
    appendLine()
    append("Собрано в приложении «ВыборВкуса»")
}
