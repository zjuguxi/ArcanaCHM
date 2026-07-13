#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT_DIR/Resources/7zz"
ARCHIVE_URL="https://7-zip.org/a/7z2601-mac.tar.xz"
ARCHIVE_SHA256="0b6b930dbf82742e3f1014c35072a6b8b3aab183fece348e7f723675f1c5bea2"
BINARY_SHA256="4d1baeaa33a40e7d8189c746a46f1be2186cc125bfcabfb63989db4e1c319247"

if [ -x "$DEST" ]; then
  EXISTING_SHA256="$(shasum -a 256 "$DEST" | awk '{print $1}')"
  if [ "$EXISTING_SHA256" = "$BINARY_SHA256" ]; then
    echo "$DEST already exists and its checksum is valid, skipping download."
    exit 0
  fi
  echo "Existing 7zz checksum mismatch: expected $BINARY_SHA256, got $EXISTING_SHA256" >&2
  exit 1
fi

echo "Downloading 7-Zip (macOS universal)…"
TMP_TAR="$(mktemp /tmp/7zz-download-XXXXX.tar.xz)"
trap 'rm -f "$TMP_TAR"' EXIT

for i in 1 2 3; do
  if curl --proto '=https' --tlsv1.2 -fL --connect-timeout 30 --max-time 120 -o "$TMP_TAR" "$ARCHIVE_URL"; then
    ACTUAL_SHA256="$(shasum -a 256 "$TMP_TAR" | awk '{print $1}')"
    if [ "$ACTUAL_SHA256" != "$ARCHIVE_SHA256" ]; then
      echo "7-Zip checksum mismatch: expected $ARCHIVE_SHA256, got $ACTUAL_SHA256" >&2
      exit 1
    fi
    tar xf "$TMP_TAR" -C "$(dirname "$DEST")" 7zz
    EXTRACTED_SHA256="$(shasum -a 256 "$DEST" | awk '{print $1}')"
    if [ "$EXTRACTED_SHA256" != "$BINARY_SHA256" ]; then
      rm -f "$DEST"
      echo "Extracted 7zz checksum mismatch: expected $BINARY_SHA256, got $EXTRACTED_SHA256" >&2
      exit 1
    fi
    chmod +x "$DEST"
    echo "Downloaded $DEST"
    exit 0
  fi
  echo "Attempt $i failed, retrying…" >&2
  sleep 5
done
echo "Failed to download 7zz after 3 attempts." >&2
exit 1
