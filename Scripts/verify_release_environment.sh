#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

for command in codesign hdiutil security spctl xcrun; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Error: required release tool is unavailable: $command" >&2
    exit 1
  fi
done

if [ -z "${APPLE_SIGNING_IDENTITY:-}" ] || [ "$APPLE_SIGNING_IDENTITY" = "-" ]; then
  echo "Error: APPLE_SIGNING_IDENTITY must name a Developer ID Application certificate." >&2
  exit 1
fi

if ! security find-identity -v -p codesigning | grep -F "\"$APPLE_SIGNING_IDENTITY\"" >/dev/null; then
  echo "Error: the configured signing identity is not available in the active keychains." >&2
  exit 1
fi

plutil -lint "$ROOT_DIR/Resources/ArcanaCHM.entitlements" "$ROOT_DIR/Resources/Extractor.entitlements"
xcrun notarytool --version
echo "Release environment is ready for Developer ID signing and notarization."
