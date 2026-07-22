# Quickstart — Asset Recovery App

Run this on **your own machine** (where the Flutter + Android SDKs are
installed). The folder name has spaces, so quote it in shells.

## ⚠️ Important: don't build inside the OneDrive / Cowork folder

This project syncs through OneDrive, and OneDrive **resurrects deleted files** —
it has already reintroduced the old pre-refactor layout (`lib/features/`,
`lib/state/`, `lib/shared/`, a duplicate `asset_recovery_app/` folder), which
breaks the build with duplicate/stale files.

**Fix (do this once):** copy the project OUT of the synced folder to a plain dev
directory, and build there:

```powershell
# Windows PowerShell — adjust the source path to where VS Code shows the folder
$src = "$env:USERPROFILE\OneDrive\Documents\Cowork\Asset Recovery App"
$dst = "$env:USERPROFILE\develop\asset-recovery-app"
Copy-Item -Recurse -Force "$src" "$dst"
cd "$dst"
```

The `run.sh` / `run.bat` scripts below **also auto-delete** those stale paths
each run, so they self-heal even if a sync reintroduces them.

## TL;DR

```bash
cd "Asset Recovery App"

# macOS / Linux  (use 'bash' so it runs even without the +x bit after download)
bash scripts/run.sh            # setup + analyze + test + run
bash scripts/run.sh test       # just analyze + test
bash scripts/run.sh web        # run in Chrome (no Android needed)
#   (or: chmod +x scripts/run.sh  then  ./scripts/run.sh)

# Windows (PowerShell or CMD)
scripts\run.bat                # setup + analyze + test + run
scripts\run.bat test
scripts\run.bat web
```

## What the script does

1. `flutter --version` and `flutter doctor` (toolchain sanity check)
2. `flutter create . --platforms=android,ios,web` — fills in the platform
   runners + Gradle wrapper **without** overwriting the bundled `android/`
   config (which pins `minSdk = 26`, Android 8.0+)
3. `flutter pub get` — resolves packages (provider, get_it, intl, …)
4. `flutter analyze` — static analysis
5. `flutter test` — unit + widget tests
6. `flutter run` — launches the app (skipped in `test` mode; targets Chrome in
   `web` mode)

## Manual steps (if you prefer not to use the script)

```bash
cd "Asset Recovery App"
flutter doctor -v                                # verify Flutter sees the Android SDK
flutter create . --platforms=android,ios,web
flutter pub get
flutter analyze
flutter test
flutter test integration_test                    # full E2E (needs a device/emulator)
flutter run                                       # or: flutter run -d chrome
```

## If Flutter can't find the Android SDK

```bash
flutter config --android-sdk "C:\Users\<you>\AppData\Local\Android\Sdk"   # Windows
flutter config --android-sdk "$HOME/Android/Sdk"                            # macOS/Linux
flutter doctor --android-licenses                                          # accept licenses
```

## Choosing where it runs

- **Emulator:** `flutter emulators` → `flutter emulators --launch <id>` → `flutter run`
- **Physical phone:** enable USB debugging, plug in, `flutter run`
- **Browser (fastest check):** `flutter run -d chrome`

Demo login is pre-filled: **FA-RM-01** / any password.

## Hit an error?

Copy the output of `flutter analyze` / `flutter test` and send it back — the code
can be fixed from the workspace even though it can't be compiled there.
