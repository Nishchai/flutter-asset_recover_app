# Flutter's Gradle plugin adds its own keep rules; plugin AARs (ML Kit,
# CameraX, Maps) ship consumer rules. Add app-specific rules below.
-dontwarn com.google.android.play.core.**
