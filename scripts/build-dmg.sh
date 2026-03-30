#!/bin/bash
set -euo pipefail

command -v create-dmg >/dev/null 2>&1 || { echo "Error: create-dmg not found. Install: brew install create-dmg"; exit 1; }

# VoiceBridge DMG 构建脚本
# 用法: ./scripts/build-dmg.sh [version]
# 示例: ./scripts/build-dmg.sh 1.0.0
# 不传版本号则默认为 "dev"

VERSION="${1:-dev}"

SCHEME="VoiceBridge"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/$SCHEME.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
APP_PATH="$EXPORT_PATH/$SCHEME.app"
DMG_PATH="$BUILD_DIR/$SCHEME-${VERSION}.dmg"

echo "=== VoiceBridge DMG Builder ==="
echo "Version: $VERSION"
echo ""

# CI 环境：从环境变量导入签名证书
if [ "${CI:-}" = "true" ]; then
    echo "[CI] Importing signing certificate..."
    KEYCHAIN_PATH="$RUNNER_TEMP/build.keychain-db"
    KEYCHAIN_PASSWORD="$(openssl rand -base64 32)"

    security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
    security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
    security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

    echo "$CERTIFICATE_P12" | base64 --decode > "$RUNNER_TEMP/certificate.p12"
    security import "$RUNNER_TEMP/certificate.p12" \
        -P "$CERTIFICATE_PASSWORD" \
        -A \
        -t cert \
        -f pkcs12 \
        -k "$KEYCHAIN_PATH"
    security set-key-partition-list -S apple-tool:,apple: -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
    security list-keychains -d user -s "$KEYCHAIN_PATH" login.keychain-db

    echo "[CI] Certificate imported."
fi

# 构建版本参数
VERSION_OVERRIDES=()
if [ "$VERSION" != "dev" ]; then
    echo "[*] Will build with version $VERSION"
    VERSION_OVERRIDES=(MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$VERSION")
fi

# 清理旧构建
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Step 1: Archive
echo "[1/5] Archiving..."
xcodebuild archive \
    -project "$PROJECT_DIR/VoiceBridge.xcodeproj" \
    -scheme "$SCHEME" \
    -archivePath "$ARCHIVE_PATH" \
    -configuration Release \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM=97ZLXJHDD3 \
    "${VERSION_OVERRIDES[@]}"

# Step 2: Export
echo "[2/5] Exporting..."

cat > "$BUILD_DIR/ExportOptions.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist"

# Step 3: Notarize
echo "[3/5] Notarizing..."
ditto -c -k --keepParent "$APP_PATH" "$BUILD_DIR/$SCHEME.zip"

if [ "${CI:-}" = "true" ]; then
    xcrun notarytool submit "$BUILD_DIR/$SCHEME.zip" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_ID_PASSWORD" \
        --team-id "$APPLE_TEAM_ID" \
        --wait
else
    xcrun notarytool submit "$BUILD_DIR/$SCHEME.zip" \
        --keychain-profile "notarytool-profile" \
        --wait
fi

# Step 4: Staple
echo "[4/5] Stapling..."
xcrun stapler staple "$APP_PATH"

# Step 5: Create DMG
echo "[5/5] Creating DMG..."
create-dmg \
    --volname "VoiceBridge" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 100 \
    --icon "$SCHEME.app" 175 190 \
    --app-drop-link 425 190 \
    --hide-extension "$SCHEME.app" \
    "$DMG_PATH" \
    "$APP_PATH"

echo ""
echo "=== Done! ==="
echo "DMG: $DMG_PATH"
echo ""
echo "签名验证:"
codesign --verify --verbose "$APP_PATH"
spctl --assess --type execute --verbose "$APP_PATH"

# CI 环境：清理临时钥匙串
if [ "${CI:-}" = "true" ]; then
    security delete-keychain "$KEYCHAIN_PATH" 2>/dev/null || true
fi
