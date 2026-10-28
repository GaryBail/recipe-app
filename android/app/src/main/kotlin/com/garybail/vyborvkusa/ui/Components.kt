package com.garybail.vyborvkusa.ui

import android.content.Context
import android.graphics.BitmapFactory
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.garybail.vyborvkusa.core.Recipe

// ---------- Иллюстрации Fluent Emoji из общего каталога (assets/Food) ----------

private object FoodImages {
    private val cache = object : android.util.LruCache<String, ImageBitmap>(40) {}

    fun load(context: Context, icon: String): ImageBitmap? {
        if (icon.isEmpty()) return null
        cache.get(icon)?.let { return it }
        val bitmap = runCatching {
            context.assets.open("Food/food-$icon.png").use { BitmapFactory.decodeStream(it) }
        }.getOrNull() ?: return null
        return bitmap.asImageBitmap().also { cache.put(icon, it) }
    }
}

@Composable
fun FoodImage(icon: String, size: Dp, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val image = remember(icon) { FoodImages.load(context, icon) }
    if (image != null) {
        Image(image, contentDescription = null, modifier = modifier.size(size))
    } else {
        Box(modifier.size(size))
    }
}

// ---------- Тег Ant Design ----------

@Composable
fun AntTag(text: String, palette: Palette, modifier: Modifier = Modifier, icon: ImageVector? = null) {
    Row(
        modifier
            .clip(RoundedCornerShape(AntSize.radiusSM))
            .background(palette.bg)
            .border(BorderStroke(1.dp, palette.border), RoundedCornerShape(AntSize.radiusSM))
            .padding(horizontal = 7.dp, vertical = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icon != null) {
            Icon(icon, null, tint = palette.text, modifier = Modifier.size(12.dp))
            Spacer(Modifier.width(3.dp))
        }
        Text(text, color = palette.text, fontSize = 12.sp, maxLines = 1)
    }
}

/** Выбираемый тег (фильтры, рубрики): заливка primary, когда выбран. */
@Composable
fun AntCheckableTag(text: String, checked: Boolean, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val ant = Ant.colors
    Box(
        modifier
            .clip(RoundedCornerShape(AntSize.radius))
            .background(if (checked) ant.primary else ant.bgContainer)
            .border(1.dp, if (checked) ant.primary else ant.border, RoundedCornerShape(AntSize.radius))
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 6.dp),
    ) {
        Text(text, color = if (checked) androidx.compose.ui.graphics.Color.White else ant.text, fontSize = 14.sp)
    }
}

// ---------- Карточка с «пружинящим» нажатием (как AntPressStyle) ----------

@Composable
fun PressCard(onClick: () -> Unit, modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val scale by animateFloatAsState(if (pressed) 0.97f else 1f, spring(stiffness = 600f), label = "press")
    Box(
        modifier
            .scale(scale)
            .clip(RoundedCornerShape(AntSize.radiusLG))
            .background(Ant.colors.bgContainer)
            .border(1.dp, Ant.colors.borderSecondary, RoundedCornerShape(AntSize.radiusLG))
            .clickable(interactionSource = interaction, indication = null, onClick = onClick),
    ) { content() }
}

@Composable
fun RecipeCard(recipe: Recipe, kcalPerServing: Double?, onClick: () -> Unit, modifier: Modifier = Modifier,
               rubricTitle: String? = null) {
    val ant = Ant.colors
    val palette = ant.rubric(recipe.rubric)
    PressCard(onClick, modifier.semantics { contentDescription = recipe.title }) {
        Column {
            Box(
                Modifier.fillMaxWidth().aspectRatio(1.35f).background(palette.bg),
                contentAlignment = Alignment.Center,
            ) {
                FoodImage(recipe.icon, 72.dp)
                if (rubricTitle != null) {
                    AntTag(rubricTitle, palette, Modifier.align(Alignment.TopStart).padding(8.dp))
                }
            }
            Column(Modifier.padding(10.dp)) {
                Text(recipe.title, style = MaterialTheme.typography.titleSmall, color = ant.text,
                     maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.height(40.dp))
                Spacer(Modifier.height(4.dp))
                val meta = listOfNotNull(
                    recipe.cookMinutes.takeIf { it > 0 }?.let { "$it мин" },
                    kcalPerServing?.let { "${it.toInt()} ккал" },
                ).joinToString(" · ")
                Text(meta.ifEmpty { " " }, fontSize = 12.sp, color = ant.textTertiary, maxLines = 1)
            }
        }
    }
}

// ---------- Разное ----------

@Composable
fun SectionTitle(text: String, modifier: Modifier = Modifier, action: (@Composable () -> Unit)? = null) {
    Row(modifier.fillMaxWidth().padding(top = 8.dp, bottom = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(text, style = MaterialTheme.typography.titleMedium, color = Ant.colors.text, modifier = Modifier.weight(1f))
        action?.invoke()
    }
}

/** − 4 порции + */
@Composable
fun ServingsStepper(value: Int, onChange: (Int) -> Unit, modifier: Modifier = Modifier, testTag: String = "servings") {
    val ant = Ant.colors
    Row(modifier, verticalAlignment = Alignment.CenterVertically) {
        StepButton("−", enabled = value > 1, description = "Меньше порций") { onChange(value - 1) }
        Text(
            "$value ${portionWord(value)}",
            modifier = Modifier.width(96.dp).semantics { contentDescription = "$testTag:$value" },
            color = ant.text, fontWeight = FontWeight.Medium,
            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
        )
        StepButton("+", enabled = value < 50, description = "Больше порций") { onChange(value + 1) }
    }
}

@Composable
private fun StepButton(label: String, enabled: Boolean, description: String, onClick: () -> Unit) {
    val ant = Ant.colors
    Box(
        Modifier.size(36.dp).clip(RoundedCornerShape(AntSize.radius))
            .border(1.dp, ant.border, RoundedCornerShape(AntSize.radius))
            .background(ant.bgContainer)
            .clickable(enabled = enabled, onClick = onClick)
            .semantics { contentDescription = description },
        contentAlignment = Alignment.Center,
    ) {
        Text(label, fontSize = 20.sp, color = if (enabled) ant.text else ant.textTertiary)
    }
}

fun portionWord(n: Int): String {
    val mod100 = n % 100
    val mod10 = n % 10
    return when {
        mod100 in 11..14 -> "порций"
        mod10 == 1 -> "порция"
        mod10 in 2..4 -> "порции"
        else -> "порций"
    }
}

@Composable
fun EmptyState(title: String, text: String, modifier: Modifier = Modifier, icon: String = "",
               action: Pair<String, () -> Unit>? = null) {
    Column(modifier.fillMaxSize().padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally,
           verticalArrangement = Arrangement.Center) {
        if (icon.isNotEmpty()) FoodImage(icon, 72.dp)
        Spacer(Modifier.height(12.dp))
        Text(title, style = MaterialTheme.typography.titleMedium, color = Ant.colors.text)
        Spacer(Modifier.height(6.dp))
        Text(text, color = Ant.colors.textSecondary, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
        if (action != null) {
            Spacer(Modifier.height(8.dp))
            TextButton(onClick = action.second) { Text(action.first) }
        }
    }
}

/** Карточка-контейнер (как Section в iOS). */
@Composable
fun AntCard(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Box(
        modifier.fillMaxWidth()
            .clip(RoundedCornerShape(AntSize.radiusLG))
            .background(Ant.colors.bgContainer)
            .border(1.dp, Ant.colors.borderSecondary, RoundedCornerShape(AntSize.radiusLG))
            .padding(AntSize.paddingSM),
    ) { content() }
}

fun rub(value: java.math.BigDecimal): String {
    val rounded = value.setScale(0, java.math.RoundingMode.HALF_UP).toPlainString()
    return rounded.reversed().chunked(3).joinToString(" ").reversed() + " ₽"
}
