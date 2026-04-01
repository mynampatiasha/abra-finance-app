@echo off
echo ========================================
echo  Abra Finance Suite - Play Store Build
echo ========================================

:: Set your keystore credentials here before running
set KEY_ALIAS=abrafinance
set KEY_PASSWORD=AbraFinance
set STORE_FILE=keystore/abrafinance.jks
set STORE_PASSWORD=AbraFinance

echo Cleaning previous build...
call flutter clean

echo Getting dependencies...
call flutter pub get

echo Building release AAB for Play Store...
call flutter build appbundle --release

echo.
echo ========================================
echo  Build complete!
echo  AAB location:
echo  build\app\outputs\bundle\release\app-release.aab
echo  Upload this file to Google Play Console
echo ========================================
pause
