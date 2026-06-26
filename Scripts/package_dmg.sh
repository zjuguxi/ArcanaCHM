#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="ArcanaCHM"
VERSION="$1"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/${APP_NAME}.app"
DMG_PATH="$DIST_DIR/$DMG_NAME"
STAGING="$DIST_DIR/.staging"
RW_DMG="$DIST_DIR/.template.dmg"
VOL_NAME="${APP_NAME} ${VERSION}"

if [ ! -d "$APP_DIR" ]; then
  echo "Error: $APP_DIR not found. Run Scripts/package_app.sh first."
  exit 1
fi

# Detach any stale mounts of the same volume
for mount in $(hdiutil info 2>/dev/null | grep -i "$VOL_NAME" | grep -o "/dev/disk[0-9]*"); do
  hdiutil detach "$mount" 2>/dev/null || true
done

# Prepare staging area
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP_DIR" "$STAGING"
ln -s /Applications "$STAGING/Applications"

# Create read-write DMG
rm -f "$RW_DMG"
hdiutil create -volname "$VOL_NAME" \
  -srcfolder "$STAGING" \
  -ov -fs HFS+ \
  -format UDRW \
  "$RW_DMG"

# Mount and set icon layout
hdiutil attach -readwrite -noverify "$RW_DMG" 2>/dev/null

# Find actual mount path (macOS may append a number)
MOUNT_DIR=""
for try in "/Volumes/$VOL_NAME"*; do
  if [ -d "$try" ]; then
    MOUNT_DIR="$try"
    break
  fi
done

sleep 1

osascript &>/dev/null <<EOF || true
tell application "Finder"
  set theDisk to disk "$(basename "$MOUNT_DIR")"
  open theDisk
  set current view of container window of theDisk to icon view
  set toolbar visible of container window of theDisk to false
  set statusbar visible of container window of theDisk to false
  set the bounds of container window of theDisk to {400, 200, 880, 520}
  set viewOptions to the icon view options of container window of theDisk
  set arrangement of viewOptions to not arranged
  set icon size of viewOptions to 104
  try
    set position of item "$APP_NAME.app" of container window of theDisk to {152, 220}
  end try
  try
    set position of item "Applications" of container window of theDisk to {440, 220}
  end try
  close
end tell
EOF

sync

# Detach by finding disk for this mount point
DISK=$(df "$MOUNT_DIR" 2>/dev/null | tail -1 | awk '{print $1}' | xargs basename 2>/dev/null || echo "")
if [ -n "$DISK" ]; then
  hdiutil detach "/dev/$DISK" 2>/dev/null || hdiutil detach -force "/dev/$DISK" 2>/dev/null || true
else
  # Fallback: detach all mounts of the template DMG
  for mount in $(hdiutil info 2>/dev/null | grep "$RW_DMG" | grep -o "/dev/disk[0-9]*"); do
    hdiutil detach "$mount" 2>/dev/null || true
  done
fi

# Convert to compressed read-only DMG
rm -f "$DMG_PATH"
hdiutil convert "$RW_DMG" -ov -format UDZO -o "$DMG_PATH"

# Clean up
rm -f "$RW_DMG"
rm -rf "$STAGING"

echo "$DMG_PATH"
