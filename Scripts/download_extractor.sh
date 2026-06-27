#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT_DIR/Resources/7zz"

if [ -x "$DEST" ]; then
  echo "$DEST already exists, skipping download."
  exit 0
fi

echo "Downloading 7-Zip (macOS universal)…"
TMP_TAR="$(mktemp /tmp/7zz-download-XXXXX.tar.xz)"
trap 'rm -f "$TMP_TAR"' EXIT

curl -fL -o "$TMP_TAR" "https://7-zip.org/a/7z2601-mac.tar.xz"
tar xf "$TMP_TAR" -C "$(dirname "$DEST")" 7zz
chmod +x "$DEST"
echo "Downloaded $DEST"
