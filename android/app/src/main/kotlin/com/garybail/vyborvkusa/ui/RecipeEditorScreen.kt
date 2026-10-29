package com.garybail.vyborvkusa.ui

import android.graphics.BitmapFactory
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.garybail.vyborvkusa.AppModel
import com.garybail.vyborvkusa.StepPhotos
import com.garybail.vyborvkusa.core.CommunityIngredient
import com.garybail.vyborvkusa.core.CommunityProduct
import com.garybail.vyborvkusa.core.CommunityRecipe
import com.garybail.vyborvkusa.core.FridgeMatcher
import com.garybail.vyborvkusa.core.MeasureUnit
import java.util.UUID

private class IngredientDraft(
    val id: String,
    title: String,
    categoryId: String?,
    amount: String,
    unit: MeasureUnit,
) {
    var title by mutableStateOf(title)
    /** Категория каталога («Сыр твёрдый») или null — своя, с одноимённым продуктом. */
    var categoryId by mutableStateOf(categoryId)
    var amount by mutableStateOf(amount)
    var unit by mutableStateOf(unit)
}

private class StepDraft(val key: String, text: String) {
    var text by mutableStateOf(text)
}

/** Свой рецепт: ингредиенты с категориями каталога (чтобы подбирать продукты и цены), шаги с фото. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun RecipeEditorScreen(model: AppModel, loaded: AppModel.Loaded, nav: Nav, recipeId: String?) {
    val ant = Ant.colors
    val context = LocalContext.current
    val existing = recipeId?.let { id -> model.data.userRecipes.firstOrNull { it.id == id } }
    val id = remember { existing?.id ?: "user-${UUID.randomUUID()}" }
    val matcher = remember { FridgeMatcher(loaded.catalog) }
    var title by remember { mutableStateOf(existing?.title.orEmpty()) }
    var summary by remember { mutableStateOf(existing?.summary.orEmpty()) }
    var servings by remember { mutableIntStateOf(existing?.servings ?: 2) }
    var rubric by remember { mutableStateOf(existing?.rubric ?: "main") }
    var minutes by remember { mutableStateOf(existing?.cookMinutes?.toString().orEmpty()) }
    val ingredients = remember {
        mutableStateListOf<IngredientDraft>().apply {
            existing?.ingredients?.forEach {
                add(IngredientDraft(it.id, it.title, it.categoryId.takeIf { c -> !c.startsWith("user-") }, MeasureUnit.number(it.amount),
                                    MeasureUnit.fromRaw(it.unit)))
            }
            if (isEmpty()) add(IngredientDraft("$id-i0", "", null, "", MeasureUnit.GRAMS))
        }
    }
    val steps = remember {
        mutableStateListOf<StepDraft>().apply {
            existing?.steps?.forEachIndexed { i, s -> add(StepDraft("s$i", s)) }
            if (isEmpty()) add(StepDraft("s0", ""))
        }
    }
    var photoStep by remember { mutableStateOf<Int?>(null) }
    var photosVersion by remember { mutableIntStateOf(0) }
    var error by remember { mutableStateOf<String?>(null) }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        val step = photoStep
        if (uri != null && step != null) {
            if (!StepPhotos.save(context, id, step, uri)) error = "Не удалось сохранить фото"
            photosVersion++
        }
    }

    fun save() {
        val valid = ingredients.filter { it.title.isNotBlank() && (it.amount.replace(',', '.').toDoubleOrNull() ?: 0.0) > 0 }
        when {
            title.isBlank() -> { error = "Назовите рецепт"; return }
            valid.isEmpty() -> { error = "Добавьте хотя бы один ингредиент с количеством"; return }
        }
        val products = mutableListOf<CommunityProduct>()
        val list = valid.mapIndexed { i, d ->
            val category = d.categoryId ?: run {
                // Своя категория: продукт с тем же названием, чтобы сборка и список покупок работали.
                val cat = "user-cat-${d.id}"
                products += CommunityProduct("user-p-${d.id}", d.title.trim(), null, cat)
                cat
            }
            CommunityIngredient("$id-i$i".takeIf { existing == null } ?: d.id, d.title.trim(), category,
                                d.amount.replace(',', '.').toDouble(), d.unit.raw)
        }
        val recipe = CommunityRecipe(id, title.trim(), summary.trim(), servings,
                                     steps.map { it.text.trim() }.filter { it.isNotEmpty() }, list,
                                     rubric, minutes.toIntOrNull()?.takeIf { it > 0 })
        model.saveUserRecipe(recipe, products)
        nav.back()
        if (existing == null) nav.recipe(id)
    }

    ScreenScaffold(if (existing == null) "Новый рецепт" else "Изменить рецепт", onBack = { nav.back() },
                   bottomBar = {
                       Box(Modifier.fillMaxWidth().padding(12.dp)) {
                           Button(onClick = ::save, modifier = Modifier.fillMaxWidth().testTag("save-recipe")) { Text("Сохранить рецепт") }
                       }
                   }) { padding ->
        LazyColumn(Modifier.padding(padding).fillMaxSize(), contentPadding = PaddingValues(16.dp),
                   verticalArrangement = Arrangement.spacedBy(10.dp)) {
            item {
                OutlinedTextField(title, { title = it.take(100) }, label = { Text("Название") }, singleLine = true,
                                  modifier = Modifier.fillMaxWidth().testTag("recipe-title"))
            }
            item {
                OutlinedTextField(summary, { summary = it.take(500) }, label = { Text("Коротко о блюде") },
                                  modifier = Modifier.fillMaxWidth())
            }
            item {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    ServingsStepper(servings, { servings = it })
                    OutlinedTextField(minutes, { minutes = it.filter(Char::isDigit).take(4) }, label = { Text("Минут") },
                                      singleLine = true, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                                      modifier = Modifier.padding(start = 12.dp).weight(1f))
                }
            }
            item {
                FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    loaded.catalog.rubrics.forEach { r -> AntCheckableTag(r.title, rubric == r.id, { rubric = r.id }) }
                }
            }
            item { SectionTitle("Ингредиенты") }
            itemsIndexed(ingredients, key = { _, d -> d.id }) { _, d ->
                AntCard {
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            OutlinedTextField(d.title, { d.title = it.take(100); d.categoryId = null }, label = { Text("Что") },
                                              singleLine = true, modifier = Modifier.weight(1f).testTag("ingredient-title"))
                            IconButton(onClick = { ingredients.remove(d) }, enabled = ingredients.size > 1) {
                                Icon(Icons.Filled.Close, "Убрать ингредиент")
                            }
                        }
                        val category = d.categoryId
                        if (category != null) {
                            AntTag("Категория: ${loaded.catalog.categoryTitle(category)}", ant.green)
                        } else if (d.title.trim().length >= 3) {
                            val options = remember(d.title) { matcher.categories(d.title).take(4) }
                            if (options.isNotEmpty()) {
                                Text("Из каталога — подберём продукты и цены:", fontSize = 12.sp, color = ant.textTertiary)
                                FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                    options.forEach { (cid, ctitle) ->
                                        AntCheckableTag(ctitle, false, { d.categoryId = cid }, Modifier.testTag("category-option"))
                                    }
                                }
                            }
                        }
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            OutlinedTextField(d.amount, { d.amount = it.filter { c -> c.isDigit() || c == ',' || c == '.' }.take(7) },
                                              label = { Text("Сколько") }, singleLine = true,
                                              keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                                              modifier = Modifier.width(110.dp).testTag("ingredient-amount"))
                            MeasureUnit.entries.forEach { u -> AntCheckableTag(u.short, d.unit == u, { d.unit = u }) }
                        }
                    }
                }
            }
            item {
                TextButton(onClick = {
                    ingredients += IngredientDraft("$id-i${UUID.randomUUID().toString().take(8)}", "", null, "", MeasureUnit.GRAMS)
                }) { Icon(Icons.Filled.Add, null); Text("Ингредиент") }
            }
            item { SectionTitle("Шаги") }
            itemsIndexed(steps, key = { _, s -> s.key }) { index, step ->
                AntCard {
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            OutlinedTextField(step.text, { step.text = it.take(1000) }, label = { Text("Шаг ${index + 1}") },
                                              modifier = Modifier.weight(1f))
                            IconButton(onClick = { steps.remove(step) }, enabled = steps.size > 1) { Icon(Icons.Filled.Close, "Убрать шаг") }
                        }
                        val photo = remember(photosVersion, index) { StepPhotos.file(context, id, index + 1) }
                        if (photo != null) {
                            val bitmap = remember(photo, photosVersion) { BitmapFactory.decodeFile(photo.path)?.asImageBitmap() }
                            if (bitmap != null) {
                                Image(bitmap, null, contentScale = ContentScale.Crop,
                                      modifier = Modifier.fillMaxWidth().height(160.dp).clip(RoundedCornerShape(AntSize.radius)))
                            }
                        }
                        Row {
                            OutlinedButton(onClick = {
                                photoStep = index + 1
                                picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                            }) { Text(if (photo == null) "Добавить фото" else "Заменить фото") }
                            if (photo != null) {
                                TextButton(onClick = { StepPhotos.delete(context, id, index + 1); photosVersion++ }) { Text("Убрать фото") }
                            }
                        }
                    }
                }
            }
            item {
                TextButton(onClick = { steps += StepDraft("s${UUID.randomUUID()}", "") }) { Icon(Icons.Filled.Add, null); Text("Шаг") }
            }
            error?.let { item { Text(it, color = ant.error) } }
        }
    }
}
