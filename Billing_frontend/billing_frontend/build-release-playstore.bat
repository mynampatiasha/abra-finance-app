@echo off
echo ========================================
echo  Abra Finance Suite - Play Store Build
echo ========================================

echo Step 1: Switching to PRODUCTION URL...
powershell -Command "(Get-Content .env) -replace '^FINANCE_API_BASE_URL=http://localhost:3002', '# FINANCE_API_BASE_URL=http://localhost:3002' | Set-Content .env"
powershell -Command "(Get-Content .env) -replace '^# FINANCE_API_BASE_URL=https://finance.abragroup.in', 'FINANCE_API_BASE_URL=https://finance.abragroup.in' | Set-Content .env"
echo   -> FINANCE_API_BASE_URL set to https://finance.abragroup.in

echo Step 2: Cleaning previous build...
call flutter clean

echo Step 3: Getting dependencies...
call flutter pub get

echo Step 4: Generating app icons from abra_finance_logo.jpg...
call dart run flutter_launcher_icons

echo Step 5: Building release AAB for Play Store...
call flutter build appbundle --release

echo Step 6: Restoring LOCAL development URL...
powershell -Command "(Get-Content .env) -replace '^FINANCE_API_BASE_URL=https://finance.abragroup.in', '# FINANCE_API_BASE_URL=https://finance.abragroup.in' | Set-Content .env"
powershell -Command "(Get-Content .env) -replace '^# FINANCE_API_BASE_URL=http://localhost:3002', 'FINANCE_API_BASE_URL=http://localhost:3002' | Set-Content .env"
echo   -> FINANCE_API_BASE_URL restored to localhost:3002

echo.
echo ========================================
echo  Build complete!
echo  AAB location:
echo  build\app\outputs\bundle\release\app-release.aab
echo  Upload this file to Google Play Console
echo ========================================
pause
