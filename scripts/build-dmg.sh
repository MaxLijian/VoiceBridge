#!/bin/bash
set -euo pipefail

# VoiceBridge DMG 构建脚本
# 用法: ./scripts/build-dmg.sh

SCHEME="VoiceBridge"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/$SCHEME.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
APP_PATH="$EXPORT_PATH/$SCHEME.app"
DMG_PATH="$BUILD_DIR/$SCHEME.dmg"

echo "=== VoiceBridge DMG Builder ==="
echo ""

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
    | tail -1

# Step 2: Export
echo "[2/5] Exporting..."

# 创建 ExportOptions.plist
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
    -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
    | tail -1

# Step 3: Notarize
echo "[3/5] Notarizing..."
xcrun notarytool submit "$APP_PATH" \
    --keychain-profile "notarytool-profile" \
    --wait

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
