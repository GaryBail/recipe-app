pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "VyborVkusa"

// core — каталог и расчёты на чистом Kotlin (без Android): позже его можно сделать общим с iOS (Kotlin Multiplatform).
// app — приложение Android на Jetpack Compose.
include(":core", ":app")
