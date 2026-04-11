@echo off
echo ========================================
echo  Abra Finance Suite - Local Test APK
echo  (uses localhost:3002 backend)
echo ========================================

echo Step 1: Getting dependencies...
call flutter pub get

echo Step 2: Building debug APK for local testing...
call flutter build apk --debug

echo.
echo ========================================
echo  APK location:
echo  build\app\outputs\flutter-apk\app-debug.apk
echo  Install on your phone for local testing
echo ========================================
pause
