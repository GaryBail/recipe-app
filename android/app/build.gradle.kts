import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.garybail.vyborvkusa"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.garybail.vyborvkusa"
        minSdk = 26          // Android 8.0+: почти все телефоны среднего сегмента
        targetSdk = 35
        versionCode = (System.getenv("VERSION_CODE") ?: "1").toInt()
        versionName = "0.1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        // Адрес сервера для сборки (как VV_SERVER_URL в iOS). Пусто — тестовые цены, адрес можно указать в профиле.
        buildConfigField("String", "SERVER_URL", "\"${providers.gradleProperty("vvServerUrl").getOrElse("")}\"")
        buildConfigField("boolean", "ALLOW_SERVER_OVERRIDE",
                         providers.gradleProperty("vvAllowServerOverride").getOrElse("true"))
    }

    // Тестовый ключ подписи лежит в репозитории, чтобы новые сборки ставились поверх старых.
    // Для RuStore / Google Play нужен отдельный ключ, который в репозиторий не попадает.
    signingConfigs {
        create("test") {
            storeFile = file("test.keystore")
            storePassword = "vyborvkusa"
            keyAlias = "test"
            keyPassword = "vyborvkusa"
        }
    }

    buildTypes {
        debug {
            signingConfig = signingConfigs.getByName("test")
        }
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("test")
        }
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    // Каталог и иллюстрации — те же файлы, что в iOS (RecipeApp/Resources): seed.json и Food/*.png.
    sourceSets["main"].assets.srcDirs("../../RecipeApp/Resources")

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    packaging {
        resources.excludes += "/META-INF/{AL2.0,LGPL2.1}"
    }

    testOptions {
        animationsDisabled = true
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencies {
    implementation(project(":core"))

    val composeBom = platform("androidx.compose:compose-bom:2024.12.01")
    implementation(composeBom)
    androidTestImplementation(composeBom)

    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")
    implementation("androidx.navigation:navigation-compose:2.8.5")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-core")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    debugImplementation("androidx.compose.ui:ui-tooling")

    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.compose.ui:ui-test-junit4")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
}
