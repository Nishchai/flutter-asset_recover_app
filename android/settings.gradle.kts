pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val flutterSdkPath = properties.getProperty("flutter.sdk")
        require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
        flutterSdkPath
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    // AGP 8.13.x is the newest 8.x line; it requires Gradle >= 8.13 (the wrapper
    // pins 8.14.5). Both sit inside what the pinned Flutter SDK validates
    // against — it supports up to Gradle 9.3.1 / AGP 9.1 — so this clears the
    // "support will soon be dropped" warnings without moving to the AGP 9
    // major, whose breaking changes the plugin set here has not been proven on.
    id("com.android.application") version "8.13.2" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
}

include(":app")
