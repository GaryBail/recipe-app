package com.garybail.vyborvkusa

import android.graphics.Bitmap
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasText
import androidx.test.rule.GrantPermissionRule
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
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
    @get:Rule(order = 0)
    val permissions: GrantPermissionRule =
        if (android.os.Build.VERSION.SDK_INT >= 33) GrantPermissionRule.grant(android.Manifest.permission.POST_NOTIFICATIONS)
        else GrantPermissionRule.grant()

    @get:Rule(order = 1)
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
        val file = File(dir, String.format("%02d-%s.png", index, name))
        file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        // После тестов AGP удаляет приложение вместе с его файлами — копируем туда, откуда CI заберёт.
        shell("mkdir -p /data/local/tmp/screens")
        shell("cp ${file.absolutePath} /data/local/tmp/screens/")
    }

    private fun shell(command: String) {
        InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand(command).use { fd ->
            java.io.FileInputStream(fd.fileDescriptor).use { it.readBytes() }
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
        rule.onNodeWithTag("segment-1").performClick()
        shot("my-builds")

        tab("profile")
        rule.waitUntilExactlyOneExists(hasTestTag("profile"))
        shot("profile")

        tab("home")
        rule.waitUntilAtLeastOneExists(hasTestTag("home"), timeoutMillis = 5_000)
        rule.onAllNodesWithTag("home").onFirst().performScrollToNode(hasTestTag("search"))
        rule.onNodeWithContentDescription("Очистить").performClick()
        rule.onAllNodesWithTag("home").onFirst().performScrollToNode(hasTestTag("fridge-link"))
        rule.onNodeWithTag("fridge-link").performClick()
        rule.onNodeWithTag("fridge-query").performTextInput("яйц")
        rule.onAllNodesWithText("Яйц", substring = true).onFirst().performClick()
        rule.onNodeWithTag("fridge-query").performTextInput("молок")
        rule.onAllNodesWithText("Молок", substring = true).onFirst().performClick()
        shot("fridge")

        // Дальше — с настоящим сервером (CI запускает его рядом с эмулятором и передаёт адрес).
        val server = InstrumentationRegistry.getArguments().getString("serverUrl") ?: return
        withServer(server)
    }

    private val anyQuote = SemanticsMatcher("quote-*") {
        it.config.getOrNull(SemanticsProperties.TestTag)?.startsWith("quote-") == true
    }

    private fun withServer(server: String) {
        tab("profile")
        rule.waitUntilExactlyOneExists(hasTestTag("profile"))
        rule.onNodeWithTag("profile").performScrollToNode(hasTestTag("server-url"))
        rule.onNodeWithTag("server-url").performTextInput(server)
        rule.onNodeWithTag("profile").performScrollToNode(hasTestTag("login"))
        rule.onNodeWithTag("login").performClick()
        rule.waitUntilExactlyOneExists(hasTestTag("auth-email"))
        rule.onNodeWithTag("auth-email").performTextInput("demo@vyborvkusa.test")
        rule.onNodeWithTag("auth-password").performTextInput("demo12345")
        shot("login")
        rule.onNodeWithTag("auth-submit").performClick()
        rule.waitUntilExactlyOneExists(hasTestTag("bell"), timeoutMillis = 20_000)
        shot("profile-account")

        rule.onNodeWithTag("bell").performClick()
        rule.waitUntilAtLeastOneExists(hasText("Отличный выбор сыра", substring = true), timeoutMillis = 15_000)
        shot("notifications")

        tab("community")
        rule.waitUntilAtLeastOneExists(hasTestTag("community-build"), timeoutMillis = 20_000)
        shot("community")
        rule.onAllNodesWithText("Бабушкин пирог", substring = true).onFirst().performClick()
        rule.waitUntilExactlyOneExists(hasTestTag("community-build-detail"), timeoutMillis = 15_000)
        shot("community-build")
        rule.onNodeWithTag("save-community").performClick()
        rule.waitUntilExactlyOneExists(hasTestTag("build"))
        shot("saved-build")

        // Живые цены Ленты, Магнита, Ашана, ВкусВилла и Купера через наш сервер.
        rule.onNodeWithTag("compare").performClick()
        rule.waitUntilAtLeastOneExists(anyQuote, timeoutMillis = 120_000)
        shot("compare-live")
        rule.onAllNodes(anyQuote).onFirst().performClick()
        shot("compare-live-details")

        tab("favorites")
        rule.onNodeWithTag("segment-2").performClick()
        rule.onNodeWithTag("new-recipe").performClick()
        rule.waitUntilExactlyOneExists(hasTestTag("recipe-title"))
        rule.onNodeWithTag("recipe-title").performTextInput("Сырники по-маминому")
        rule.onNodeWithTag("ingredient-title").performTextInput("Творог")
        rule.waitUntilAtLeastOneExists(hasTestTag("category-option"))
        rule.onAllNodesWithTag("category-option").onFirst().performClick()
        rule.onNodeWithTag("ingredient-amount").performTextInput("400")
        shot("recipe-editor")
        rule.onNodeWithTag("save-recipe").performClick()
        rule.waitUntilExactlyOneExists(hasTestTag("recipe"))
        shot("own-recipe")
    }
}
