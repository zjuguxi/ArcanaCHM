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

for i in 1 2 3; do
  if curl -fL --connect-timeout 30 --max-time 120 -o "$TMP_TAR" "https://7-zip.org/a/7z2601-mac.tar.xz"; then
    tar xf "$TMP_TAR" -C "$(dirname "$DEST")" 7zz
    chmod +x "$DEST"
    echo "Downloaded $DEST"
    exit 0
  fi
  echo "Attempt $i failed, retrying…" >&2
  sleep 5
done
echo "Failed to download 7zz after 3 attempts." >&2
exit 1
