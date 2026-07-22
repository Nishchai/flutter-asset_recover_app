#!/usr/bin/env bash
#
# Asset Recovery App — setup / test / run helper (macOS & Linux).
#
# Usage:
#   ./scripts/run.sh          full: setup + analyze + test + run on a device
#   ./scripts/run.sh test     setup + analyze + test only (no app launch)
#   ./scripts/run.sh web      setup + analyze + run in Chrome (skips device test)
#   ./scripts/run.sh setup    setup only (create platforms + pub get)
#
set -euo pipefail

# Always run from the project root (parent of this script's dir).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

MODE="${1:-full}"

step() { printf '\n\033[1;33m▶ %s\033[0m\n' "$1"; }

if ! command -v flutter >/dev/null 2>&1; then
  echo "❌ 'flutter' is not on your PATH. Install Flutter and re-open your terminal."
  echo "   https://docs.flutter.dev/get-started/install"
  exit 1
fi

step "Flutter version"
flutter --version

step "flutter doctor (toolchain check)"
flutter doctor || true   # don't abort on doctor warnings

step "Removing stale duplicate files (OneDrive sync can reintroduce the old layout)"
rm -rf lib/features lib/state lib/shared lib/core/constants lib/data/models \
       lib/app.dart lib/core/app_services.dart lib/data/repositories/ticket_repository.dart 2>/dev/null || true

step "Generating platform runners (keeps the bundled android/ minSdk 26 config)"
flutter create . --platforms=android,ios,web

step "Resolving packages"
flutter pub get

step "Static analysis"
flutter analyze

if [ "$MODE" = "setup" ]; then
  echo "✅ Setup complete."
  exit 0
fi

step "Running tests"
flutter test

case "$MODE" in
  test)
    echo "✅ Analyze + tests complete."
    ;;
  web)
    step "Launching in Chrome"
    flutter run -d chrome
    ;;
  full)
    step "Launching the app (pick a device if prompted)"
    flutter run
    ;;
  *)
    echo "Unknown mode: $MODE  (use: full | test | web | setup)"
    exit 2
    ;;
esac
