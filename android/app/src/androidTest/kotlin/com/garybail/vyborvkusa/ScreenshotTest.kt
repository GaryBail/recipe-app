package com.garybail.vyborvkusa

import android.graphics.Bitmap
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performTextInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Проходит по основным экранам и сохраняет скриншоты (CI забирает их с эмулятора). */
@OptIn(ExperimentalTestApi::class)
@RunWith(AndroidJUnit4::class)
class ScreenshotTest {
    @get:Rule
    val rule = createAndroidComposeRule<MainActivity>()

    private var index = 0
    private val dir: File by lazy {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        File(context.getExternalFilesDir(null), "screenshots").apply { mkdirs() }
    }

    private fun shot(name: String) {
        rule.waitForIdle()
        Thread.sleep(400)
        index += 1
        val bitmap = rule.onRoot().captureToImage().asAndroidBitmap()
        File(dir, String.format("%02d-%s.png", index, name)).outputStream().use {
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
        }
    }

    private fun tab(route: String) = rule.onNodeWithTag("tab-$route").performClick()

    @Test
    fun walkthrough() {
        rule.waitUntilExactlyOneExists(hasTestTag("home"), timeoutMillis = 20_000)
        shot("home")

        rule.onNodeWithTag("home").performScrollToNode(hasTestTag("filter-quick"))
        rule.onNodeWithTag("filter-quick").performClick()
        shot("home-filter-quick")
        rule.onNodeWithTag("filter-quick").performClick()

        rule.onNodeWithTag("home").performScrollToNode(hasTestTag("search"))
        rule.onNodeWithTag("search").performTextInput("карбонара")
        shot("search")
        rule.onNodeWithContentDescription("Паста карбонара").performClick()
        rule.waitUntilExactlyOneExists(hasTestTag("recipe"))
        shot("recipe")
        rule.onNodeWithTag("favorite").performClick()

        rule.onNodeWithTag("recipe").performScrollToNode(hasContentDescription("Больше порций"))
        rule.onNodeWithContentDescription("Больше порций").performClick()
        rule.onNodeWithTag("recipe").performScrollToNode(hasTestTag("add-to-shopping"))
        shot("recipe-ingredients")
        rule.onNodeWithTag("add-to-shopping").performClick()

        rule.onNodeWithTag("recipe").performScrollToNode(hasTestTag("make-build"))
        rule.onNodeWithTag("make-build").performClick()
        rule.waitUntilExactlyOneExists(hasTestTag("save-build"))
        shot("build-editor")
        rule.onNodeWithTag("save-build").performClick()
        rule.waitUntilExactlyOneExists(hasTestTag("build"))
        shot("build")

        rule.onNodeWithTag("compare").performClick()
        rule.waitUntilAtLeastOneExists(hasTestTag("quote-a"), timeoutMillis = 15_000)
        shot("compare")
        rule.onNodeWithTag("quote-a").performClick()
        shot("compare-details")

        tab("shopping")
        rule.waitUntilExactlyOneExists(hasTestTag("shopping"))
        shot("shopping")
        rule.onNodeWithTag("store-mode").performClick()
        shot("shopping-store-mode")
        rule.onNodeWithTag("store-mode").performClick()

        tab("favorites")
        shot("favorites")
        rule.onNodeWithText("Мои сборки").performClick()
        shot("my-builds")

        tab("profile")
        rule.waitUntilExactlyOneExists(hasTestTag("profile"))
        shot("profile")

        tab("home")
        rule.waitUntilExactlyOneExists(hasTestTag("home"))
        rule.onNodeWithContentDescription("Очистить").performClick()
        rule.onNodeWithTag("home").performScrollToNode(hasTestTag("fridge-link"))
        rule.onNodeWithTag("fridge-link").performClick()
        rule.onNodeWithTag("fridge-query").performTextInput("яйц")
        rule.onAllNodesWithText("Яйц", substring = true).onFirst().performClick()
        rule.onNodeWithTag("fridge-query").performTextInput("молок")
        rule.onAllNodesWithText("Молок", substring = true).onFirst().performClick()
        shot("fridge")
    }
}
