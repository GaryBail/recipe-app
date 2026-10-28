package com.garybail.vyborvkusa.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * Дизайн-токены в духе Ant Design 5 — те же, что в iOS (RecipeApp/Design/AntTheme.swift):
 * палитры, семантические цвета, скругления 4/6/8, отступы по сетке 4.
 */
@Immutable
data class Palette(val bg: Color, val border: Color, val base: Color, val text: Color)

private fun palette(c1: Long, c3: Long, c6: Long, c7: Long, dark: Boolean): Palette {
    val base = Color(c6)
    return if (!dark) Palette(Color(c1), Color(c3), base, Color(c7))
    else Palette(base.copy(alpha = 0.16f), base.copy(alpha = 0.45f), base, lerp(base, Color.White, 0.25f))
}

@Immutable
class AntColors(val dark: Boolean) {
    val blue = palette(0xFFE6F4FF, 0xFF91CAFF, 0xFF1677FF, 0xFF0958D9, dark)
    val green = palette(0xFFF6FFED, 0xFFB7EB8F, 0xFF52C41A, 0xFF389E0D, dark)
    val red = palette(0xFFFFF1F0, 0xFFFFA39E, 0xFFF5222D, 0xFFCF1322, dark)
    val volcano = palette(0xFFFFF2E8, 0xFFFFBB96, 0xFFFA541C, 0xFFD4380D, dark)
    val orange = palette(0xFFFFF7E6, 0xFFFFD591, 0xFFFA8C16, 0xFFD46B08, dark)
    val gold = palette(0xFFFFFBE6, 0xFFFFE58F, 0xFFFAAD14, 0xFFD48806, dark)
    val magenta = palette(0xFFFFF0F6, 0xFFFFADD2, 0xFFEB2F96, 0xFFC41D7F, dark)
    val cyan = palette(0xFFE6FFFB, 0xFF87E8DE, 0xFF13C2C2, 0xFF08979C, dark)
    val purple = palette(0xFFF9F0FF, 0xFFD3ADF7, 0xFF722ED1, 0xFF531DAB, dark)
    val geekblue = palette(0xFFF0F5FF, 0xFFADC6FF, 0xFF2F54EB, 0xFF1D39C4, dark)

    val primary = Color(0xFF1677FF)
    val success = Color(0xFF52C41A)
    val warning = Color(0xFFFAAD14)
    val error = Color(0xFFFF4D4F)

    val bgLayout = if (dark) Color(0xFF000000) else Color(0xFFF5F5F5)
    val bgContainer = if (dark) Color(0xFF141414) else Color.White
    val fill = if (dark) Color.White.copy(alpha = 0.08f) else Color.Black.copy(alpha = 0.04f)
    val borderSecondary = if (dark) Color(0xFF303030) else Color(0xFFF0F0F0)
    val border = if (dark) Color(0xFF424242) else Color(0xFFD9D9D9)
    val text = if (dark) Color.White.copy(alpha = 0.85f) else Color.Black.copy(alpha = 0.88f)
    val textSecondary = if (dark) Color.White.copy(alpha = 0.65f) else Color.Black.copy(alpha = 0.65f)
    val textTertiary = Color(if (dark) 0x73FFFFFF else 0x73000000)

    fun named(name: String): Palette = when (name) {
        "volcano" -> volcano
        "orange" -> orange
        "gold" -> gold
        "green" -> green
        "cyan" -> cyan
        "geekblue" -> geekblue
        "magenta" -> magenta
        "purple" -> purple
        "red" -> red
        else -> blue
    }

    /** Палитра рубрики — для тегов и фона карточек. */
    fun rubric(id: String): Palette = when (id) {
        "breakfast" -> gold
        "soup" -> volcano
        "salad" -> green
        "main" -> orange
        "side" -> cyan
        "pastry" -> magenta
        "sauce" -> purple
        else -> blue
    }
}

object AntSize {
    val radiusSM = 4.dp
    val radius = 6.dp
    val radiusLG = 8.dp
    val padding = 16.dp
    val paddingSM = 12.dp
    val paddingXS = 8.dp
}

val LocalAnt = staticCompositionLocalOf { AntColors(false) }

/** Цвета Ant в любом месте: `Ant.colors.primary`. */
object Ant {
    val colors: AntColors
        @Composable get() = LocalAnt.current
}

@Composable
fun VyborVkusaTheme(content: @Composable () -> Unit) {
    val dark = isSystemInDarkTheme()
    val ant = AntColors(dark)
    val scheme = if (dark) darkColorScheme(
        primary = ant.primary, background = ant.bgLayout, surface = ant.bgContainer,
        onBackground = ant.text, onSurface = ant.text, surfaceVariant = Color(0xFF1F1F1F),
        error = ant.error, outline = ant.border,
    ) else lightColorScheme(
        primary = ant.primary, background = ant.bgLayout, surface = ant.bgContainer,
        onBackground = ant.text, onSurface = ant.text, surfaceVariant = Color(0xFFF5F5F5),
        surfaceContainer = Color.White, error = ant.error, outline = ant.border,
    )
    val base = Typography()
    val typography = base.copy(
        headlineMedium = base.headlineMedium.copy(fontWeight = FontWeight.Bold),
        titleLarge = base.titleLarge.copy(fontWeight = FontWeight.SemiBold),
        titleMedium = base.titleMedium.copy(fontWeight = FontWeight.SemiBold),
        labelLarge = TextStyle(fontSize = 15.sp, fontWeight = FontWeight.Medium),
    )
    CompositionLocalProvider(LocalAnt provides ant) {
        MaterialTheme(colorScheme = scheme, typography = typography, content = content)
    }
}
