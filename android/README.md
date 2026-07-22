# Android module (minSdk 26 — Android 8.0+)

This folder pins the app to **Android 8.0 (Oreo, API 26) and onwards** via
`app/build.gradle.kts` → `defaultConfig { minSdk = 26 }`.

It uses the modern Flutter Gradle setup (Kotlin DSL, declarative plugins,
`dev.flutter.flutter-gradle-plugin`) and an **adaptive launcher icon** (valid
from API 26, so no PNG density buckets are required).

## Two generated files are intentionally NOT committed

These are produced locally by the Flutter toolchain on first build and are
git-ignored:

- `local.properties` — created by any `flutter` command (holds `flutter.sdk`
  and `sdk.dir`).
- `gradle/wrapper/gradle-wrapper.jar` + `gradlew` — the Gradle wrapper binary.

If the wrapper is missing, materialise it once without touching the committed
config (Flutter create skips files that already exist):

```bash
flutter create . --platforms=android
```

Then build/run normally:

```bash
flutter pub get
flutter run
```

The `compileSdk`/`targetSdk` are 34; bump them as the team's target evolves.
`minSdk` should stay at **26** to honour the Android 8+ requirement.
