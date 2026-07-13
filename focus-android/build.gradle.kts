plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose.compiler)
}

android {
    namespace = "org.bilibilifocus.android"
    compileSdk = 35

    defaultConfig {
        applicationId = "org.bilibilifocus.android"
        minSdk = 26
        targetSdk = 35
        versionCode = 2
        versionName = "1.0.1"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    implementation(project(":focus-core"))
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.material3)
    implementation("androidx.compose.material:material-icons-extended")
    implementation(libs.compose.ui.tooling.preview)
    implementation(libs.androidx.activity.compose)
    implementation(libs.coil.compose)
    implementation("io.coil-kt:coil-gif:2.7.0")
    implementation("dev.chrisbanes.haze:haze:1.5.4")
    implementation("dev.chrisbanes.haze:haze-materials:1.5.4")
    implementation(libs.media3.exoplayer)
    implementation("androidx.media3:media3-session:1.5.1")
    implementation(libs.media3.ui)
    testImplementation(kotlin("test"))
    debugImplementation(libs.compose.ui.tooling)
}
