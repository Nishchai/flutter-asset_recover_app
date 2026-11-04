import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: reads android/key.properties (gitignored). See
// android/key.properties.sample. When the file is absent (local dev, CI
// without secrets) release falls back to the debug key so
// `flutter run --release` still works, but such a build is NOT uploadable.
val keystoreProps = Properties()
val keystorePropsFile = rootProject.file("key.properties")
val hasReleaseKey = keystorePropsFile.exists()
if (hasReleaseKey) keystorePropsFile.inputStream().use { keystoreProps.load(it) }

android {
    namespace = "com.sunmobility.asset_recovery_app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(JvmTarget.JVM_1_8)
        }
    }

    defaultConfig {
        applicationId = "com.sunmobility.asset_recovery_app"

        // ── Android 8.0 (Oreo, API 26) and onwards ────────────────────────────
        // Adaptive launcher icons and the device features the recovery flow
        // relies on (camera, fused location, runtime permissions) are all
        // available from API 26, so 26 is the supported floor.
        minSdk = 26
        targetSdk = 35

        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = rootProject.file(keystoreProps.getProperty("storeFile"))
                storePassword = keystoreProps.getProperty("storePassword")
                keyAlias = keystoreProps.getProperty("keyAlias")
                keyPassword = keystoreProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKey) signingConfigs.getByName("release")
                            else signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

// ── 16 KB page-size alignment ────────────────────────────────────────────────
// Android 15+ can run with 16 KB memory pages, and every bundled .so must have
// its ELF LOAD segments aligned to 16 KB or the loader rejects it. Two prebuilt
// libraries reached the APK aligned to 4 KB, both pulled in transitively by
// `mobile_scanner` (5.2.3), which pins versions predating the fix:
//
//   libimage_processing_util_jni.so  ← androidx.camera:camera-core 1.3.3
//                                      (aligned from CameraX 1.4.0)
//   libbarhopper_v3.so               ← play-services-mlkit-barcode-scanning
//                                      18.3.0 (aligned from 18.3.1)
//
// They ship as prebuilt binaries, so the only fix is newer versions. Forcing
// them here upgrades the transitive dependency without a mobile_scanner major
// bump (7.x rewrites the Dart API that QrScanScreen is built on). Drop this
// block once mobile_scanner itself ships aligned dependencies.
configurations.all {
    resolutionStrategy {
        force(
            "androidx.camera:camera-core:1.4.2",
            "androidx.camera:camera-camera2:1.4.2",
            "androidx.camera:camera-lifecycle:1.4.2",
            "com.google.android.gms:play-services-mlkit-barcode-scanning:18.3.1",
            "com.google.mlkit:barcode-scanning:17.3.0",
        )
    }
}

flutter {
    source = "../.."
}
