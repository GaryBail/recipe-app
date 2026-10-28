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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
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
    fun tab(route: String) = controller.navigate(route) {
        popUpTo(controller.graph.findStartDestination().id) { saveState = true }
        launchSingleTop = true
        restoreState = true
    }
}

@Composable
fun AppRoot(model: AppModel) {
    VyborVkusaTheme {
        val loaded = model.loaded
        if (loaded == null) Splash() else MainContent(model, loaded)
    }
}

@Composable
private fun MainContent(model: AppModel, loaded: AppModel.Loaded) {
        val controller = rememberNavController()
        val nav = androidx.compose.runtime.remember(controller) { Nav(controller) }
        val entry by controller.currentBackStackEntryAsState()
        val current = entry?.destination?.route
        val openShopping = model.data.shopping.count { !it.isChecked }

        Scaffold(
            containerColor = Ant.colors.bgLayout,
            bottomBar = {
                if (current?.startsWith("cooking") != true) {
                    NavigationBar(containerColor = Ant.colors.bgContainer) {
                        for (tab in tabs) {
                            NavigationBarItem(
                                selected = current == tab.route,
                                onClick = { nav.tab(tab.route) },
                                icon = {
                                    if (tab.route == "shopping" && openShopping > 0) {
                                        BadgedBox(badge = { Badge { Text("$openShopping") } }) { Icon(tab.icon, null) }
                                    } else {
                                        Icon(tab.icon, null)
                                    }
                                },
                                label = { Text(tab.title) },
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
                composable("profile") { ProfileScreen(model) }
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
