# Keystore for Abra Finance Suite

Place your `abrafinance.jks` keystore file in this folder.

## Generate a new keystore (run this once):

```bash
keytool -genkey -v -keystore abrafinance.jks -keyalg RSA -keysize 2048 -validity 10000 -alias abrafinance
```

You will be prompted for:
- Store password
- Key password
- Your name / organization details

## Set environment variables before building release:

```bash
export KEY_ALIAS=abrafinance
export KEY_PASSWORD=your_key_password
export STORE_FILE=keystore/abrafinance.jks
export STORE_PASSWORD=your_store_password
```

Or on Windows (CMD):
```cmd
set KEY_ALIAS=abrafinance
set KEY_PASSWORD=your_key_password
set STORE_FILE=keystore/abrafinance.jks
set STORE_PASSWORD=your_store_password
```

## Build the release AAB:

```bash
flutter build appbundle --release
```

The AAB will be at: build/app/outputs/bundle/release/app-release.aab

## IMPORTANT: Never commit the .jks file to git!
