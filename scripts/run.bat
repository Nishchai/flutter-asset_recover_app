@echo off
REM Asset Recovery App - setup / test / run helper (Windows).
REM
REM Usage:
REM   scripts\run.bat          full: setup + analyze + test + run on a device
REM   scripts\run.bat test     setup + analyze + test only (no app launch)
REM   scripts\run.bat web      setup + analyze + run in Chrome
REM   scripts\run.bat setup    setup only (create platforms + pub get)

setlocal
REM Move to the project root (parent of this script's folder).
cd /d "%~dp0\.."

set "MODE=%~1"
if "%MODE%"=="" set "MODE=full"

where flutter >nul 2>nul
if errorlevel 1 (
  echo [ERROR] 'flutter' is not on your PATH. Install Flutter and reopen the terminal.
  echo         https://docs.flutter.dev/get-started/install
  exit /b 1
)

echo.
echo === Flutter version ===
call flutter --version

echo.
echo === flutter doctor (toolchain check) ===
call flutter doctor

echo.
echo === Cleaning stale iOS artifacts ===
if exist ios (
  echo Removing stale ios folder to avoid ephemeral cleanup failures...
  rmdir /s /q "ios"
)

echo.
echo === Removing stale duplicate files (OneDrive sync can reintroduce the old layout) ===
if exist "lib\features"   rmdir /s /q "lib\features"
if exist "lib\state"      rmdir /s /q "lib\state"
if exist "lib\shared"     rmdir /s /q "lib\shared"
if exist "lib\core\constants" rmdir /s /q "lib\core\constants"
if exist "lib\data\models"    rmdir /s /q "lib\data\models"
if exist "lib\app.dart"            del /q "lib\app.dart"
if exist "lib\core\app_services.dart" del /q "lib\core\app_services.dart"
if exist "lib\data\repositories\ticket_repository.dart" del /q "lib\data\repositories\ticket_repository.dart"

echo.
echo === Generating platform runners (keeps bundled android\ minSdk 26 config) ===
set "CREATE_RUNNERS=0"
if not exist android set "CREATE_RUNNERS=1"
if not exist web set "CREATE_RUNNERS=1"
if "%CREATE_RUNNERS%"=="1" (
  echo Platform runners missing; creating them now...
  call flutter create . --platforms=android,web || goto :error
) else (
  echo Platform runners already exist; skipping flutter create
)

echo.
echo === Resolving packages ===
call flutter pub get || goto :error

echo.
echo === Static analysis ===
call flutter analyze || goto :error

if /i "%MODE%"=="setup" (
  echo Setup complete.
  goto :eof
)

echo.
echo === Running tests ===
call flutter test || goto :error

if /i "%MODE%"=="test" (
  echo Analyze + tests complete.
  goto :eof
)

if /i "%MODE%"=="web" (
  echo.
  echo === Launching in Chrome ===
  call flutter run -d chrome
  goto :eof
)

echo.
echo === Launching the app (pick a device if prompted) ===
call flutter run
goto :eof

:error
echo.
echo [ERROR] A step failed. Copy the output above and send it back for a fix.
exit /b 1
