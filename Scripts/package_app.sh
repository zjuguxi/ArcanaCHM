#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="ArcanaCHM"
VERSION="${1:-${ARCANA_VERSION:-1.3.5}}"
BUILD_NUMBER="${ARCANA_BUILD_NUMBER:-1}"
BUILD_DIR="$ROOT_DIR/.build/release"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "Building release binary..."
cd "$ROOT_DIR"
swift build -c release

echo "Creating .app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BUILD_DIR/$APP_NAME" "$MACOS_DIR/$APP_NAME"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"

echo "Bundling 7zz extractor..."
"$ROOT_DIR/Scripts/download_extractor.sh"
cp "$ROOT_DIR/Resources/7zz" "$RESOURCES_DIR/7zz"

echo "Bundling localized resources..."
cp -R "$BUILD_DIR/${APP_NAME}_${APP_NAME}.bundle" "$RESOURCES_DIR/"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>local.arcana.chm</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string>MIT License</string>
</dict>
</plist>
PLIST

SIGNING_IDENTITY="${APPLE_SIGNING_IDENTITY:--}"
if [ "${REQUIRE_SIGNING:-0}" = "1" ] && [ "$SIGNING_IDENTITY" = "-" ]; then
  echo "Error: APPLE_SIGNING_IDENTITY is required for a release build." >&2
  exit 1
fi

echo "Signing nested extractor..."
if [ "$SIGNING_IDENTITY" = "-" ]; then
  codesign --force --sign - \
    --entitlements "$ROOT_DIR/Resources/Extractor.entitlements" \
    "$RESOURCES_DIR/7zz"
else
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" \
    --entitlements "$ROOT_DIR/Resources/Extractor.entitlements" \
    "$RESOURCES_DIR/7zz"
fi

echo "Signing application..."
if [ "$SIGNING_IDENTITY" = "-" ]; then
  codesign --force --sign - \
    --entitlements "$ROOT_DIR/Resources/ArcanaCHM.entitlements" \
    "$APP_DIR"
else
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" \
    --entitlements "$ROOT_DIR/Resources/ArcanaCHM.entitlements" \
    "$APP_DIR"
fi
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

echo "Done: $APP_DIR"
