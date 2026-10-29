package com.garybail.vyborvkusa.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.ShoppingCart
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.garybail.vyborvkusa.AppModel

private data class Tab(val route: String, val title: String, val icon: ImageVector)

private val tabs = listOf(
    Tab("home", "Рецепты", Icons.Filled.Home),
    Tab("favorites", "Избранное", Icons.Filled.Favorite),
    Tab("shopping", "Покупки", Icons.Filled.ShoppingCart),
    Tab("community", "Сообщество", Icons.Filled.Star),
    Tab("profile", "Профиль", Icons.Filled.Person),
)

/** Переходы между экранами — одно место для всех маршрутов. */
class Nav(private val controller: NavHostController) {
    fun back() = controller.popBackStack()
    fun recipe(id: String) = controller.navigate("recipe/$id")
    fun newBuild(recipeId: String) = controller.navigate("build-edit?recipe=$recipeId")
    fun editBuild(id: String) = controller.navigate("build-edit?build=$id")
    fun build(id: String, replaceEditor: Boolean = false) = controller.navigate("build/$id") {
        if (replaceEditor) popUpTo("build-edit?recipe={recipe}&build={build}") { inclusive = true }
    }
    fun compare(buildId: String) = controller.navigate("compare/$buildId")
    fun collection(id: String) = controller.navigate("collection/$id")
    fun fridge() = controller.navigate("fridge")
    fun cooking(recipeId: String) = controller.navigate("cooking/$recipeId")
    fun auth() = controller.navigate("auth")
    fun communityBuild(id: String) = controller.navigate("community-build/$id")
    fun notifications() = controller.navigate("notifications")
    fun newRecipe() = controller.navigate("recipe-edit")
    fun editRecipe(id: String) = controller.navigate("recipe-edit?id=$id")
    /** Вкладка всегда открывает свой первый экран (а не последний из истории). */
    fun tab(route: String) = controller.navigate(route) {
        popUpTo(controller.graph.findStartDestination().id)
        launchSingleTop = true
    }
}

@Composable
fun AppRoot(model: AppModel, onLoggedIn: () -> Unit = {}) {
    VyborVkusaTheme {
        val loaded = model.loaded
        // После входа в аккаунт спрашиваем разрешение на уведомления (Android 13+).
        androidx.compose.runtime.LaunchedEffect(model.account?.id) { if (model.account != null) onLoggedIn() }
        if (loaded == null) Splash() else MainContent(model, loaded)
    }
}

@Composable
private fun MainContent(model: AppModel, loaded: AppModel.Loaded) {
        val controller = rememberNavController()
        val nav = androidx.compose.runtime.remember(controller) { Nav(controller) }
        val entry by controller.currentBackStackEntryAsState()
        val current = entry?.destination?.route
        // Подсвечиваем вкладку, из которой открыт текущий экран.
        var selectedTab by androidx.compose.runtime.saveable.rememberSaveable { androidx.compose.runtime.mutableStateOf("home") }
        if (current != null && tabs.any { it.route == current } && current != selectedTab) selectedTab = current
        val openShopping = model.data.shopping.count { !it.isChecked }
        // Открыть экран по нажатию на системное уведомление.
        val pending = model.pendingRoute
        androidx.compose.runtime.LaunchedEffect(pending) {
            if (pending != null) {
                model.pendingRoute = null
                controller.navigate(pending)
            }
        }

        Scaffold(
            containerColor = Ant.colors.bgLayout,
            bottomBar = {
                if (current?.startsWith("cooking") != true) {
                    NavigationBar(containerColor = Ant.colors.bgContainer) {
                        for (tab in tabs) {
                            NavigationBarItem(
                                selected = selectedTab == tab.route,
                                onClick = { selectedTab = tab.route; nav.tab(tab.route) },
                                icon = {
                                    if (tab.route == "shopping" && openShopping > 0) {
                                        BadgedBox(badge = { Badge { Text("$openShopping") } }) { Icon(tab.icon, null) }
                                    } else {
                                        Icon(tab.icon, null)
                                    }
                                },
                                label = { Text(tab.title, maxLines = 1, softWrap = false) },
                                modifier = Modifier.testTag("tab-${tab.route}"),
                            )
                        }
                    }
                }
            },
        ) { padding ->
            NavHost(controller, startDestination = "home", modifier = Modifier.padding(padding)) {
                composable("home") { HomeScreen(model, loaded, nav) }
                composable("favorites") { FavoritesScreen(model, loaded, nav) }
                composable("shopping") { ShoppingScreen(model, loaded) }
                composable("profile") { ProfileScreen(model, nav) }
                composable("auth") { AuthScreen(model, nav) }
                composable("community") { CommunityScreen(model, loaded, nav) }
                composable("community-build/{id}") {
                    CommunityBuildScreen(model, loaded, nav, it.arguments?.getString("id").orEmpty())
                }
                composable("notifications") { NotificationsScreen(model, nav) }
                composable("recipe-edit?id={id}", arguments = listOf(navArgument("id") { type = NavType.StringType; nullable = true })) {
                    RecipeEditorScreen(model, loaded, nav, it.arguments?.getString("id"))
                }
                composable("recipe/{id}") { RecipeScreen(model, loaded, nav, it.arguments?.getString("id").orEmpty()) }
                composable(
                    "build-edit?recipe={recipe}&build={build}",
                    arguments = listOf(
                        navArgument("recipe") { type = NavType.StringType; nullable = true },
                        navArgument("build") { type = NavType.StringType; nullable = true },
                    ),
                ) {
                    BuildEditorScreen(model, loaded, nav, recipeId = it.arguments?.getString("recipe"),
                                      buildId = it.arguments?.getString("build"))
                }
                composable("build/{id}") { BuildScreen(model, loaded, nav, it.arguments?.getString("id").orEmpty()) }
                composable("compare/{id}") { CompareScreen(model, loaded, nav, it.arguments?.getString("id").orEmpty()) }
                composable("collection/{id}") {
                    CollectionScreen(loaded, nav, it.arguments?.getString("id").orEmpty())
                }
                composable("fridge") { FridgeScreen(loaded, nav) }
                composable("cooking/{id}") { CookingScreen(loaded, nav, it.arguments?.getString("id").orEmpty()) }
            }
        }
}

@Composable
private fun Splash() {
    Box(Modifier.fillMaxSize().background(Ant.colors.bgLayout), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            FoodImage("cooking", 96.dp)
            Spacer(Modifier.height(12.dp))
            Text("ВыборВкуса", style = MaterialTheme.typography.headlineMedium, color = Ant.colors.text)
        }
    }
}
