#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
VERSION="${1:-$(tr -d '[:space:]' < VERSION)}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Version must have the form MAJOR.MINOR.PATCH" >&2
  exit 1
fi

# Build each architecture separately so the script also works with Command Line Tools.
# Separate scratch paths: newer SwiftPM versions share one output folder across triples.
for ARCH in arm64 x86_64; do
  swift build -c release --triple "$ARCH-apple-macosx13.0" --product Linory --scratch-path ".build/release-$ARCH"
done
ARM_DIR="$(swift build -c release --triple arm64-apple-macosx13.0 --product Linory --scratch-path .build/release-arm64 --show-bin-path)"
INTEL_DIR="$(swift build -c release --triple x86_64-apple-macosx13.0 --product Linory --scratch-path .build/release-x86_64 --show-bin-path)"

LINORY_APP_DIR="$PWD" bash build-app.sh
APP="$PWD/Linory.app"
lipo -create "$ARM_DIR/Linory" "$INTEL_DIR/Linory" -output "$APP/Contents/MacOS/Linory"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"
# Local ad-hoc signature only: this is NOT a Developer ID signature or notarization.
codesign --force --deep --sign - "$APP"
codesign --verify --verbose=2 "$APP"
for ARCH in arm64 x86_64; do lipo "$APP/Contents/MacOS/Linory" -verify_arch "$ARCH"; done
mkdir -p dist
ARCHIVE="$PWD/dist/Linory-$VERSION-universal.zip"
rm -f "$ARCHIVE"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"
echo "Created $ARCHIVE (ad-hoc signed, not notarized)"
