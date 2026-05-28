#!/usr/bin/env bash
#
# Assemble a runnable YOLOWhisp.app bundle from the SwiftPM build.
#
# YOLOWhisp is a menu-bar (LSUIElement) app that needs Microphone and
# Accessibility permissions. Those only work from a real .app bundle with an
# Info.plist -- `swift run` won't cut it. This mirrors what CI does at release
# time so local builds behave the same.
#
# Usage:
#   ./scripts/build-app.sh [debug|release]
#
set -euo pipefail

CONFIG="${1:-debug}"
APP_NAME="YOLOWhisp"
BUNDLE_ID="com.noctusoft.yolowhisp"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="$(git describe --tags --always 2>/dev/null || echo dev)"

echo "==> Building ($CONFIG)..."
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/$APP_NAME"
if [[ ! -x "$BIN_PATH" ]]; then
  echo "error: built binary not found at $BIN_PATH" >&2
  exit 1
fi

APP_DIR="$ROOT/build/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"

echo "==> Assembling $APP_DIR..."
rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN_PATH" "$CONTENTS/MacOS/$APP_NAME"

# Copy the SwiftPM resource bundle (Bundle.module) so bundled resources
# (e.g. the Diagnostics self-test WAV) resolve inside the .app.
BUNDLE_SRC="$(dirname "$BIN_PATH")/${APP_NAME}_${APP_NAME}.bundle"
if [[ -d "$BUNDLE_SRC" ]]; then
  cp -R "$BUNDLE_SRC" "$CONTENTS/Resources/"
fi

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleVersion</key>
  <string>$VERSION</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>YOLOWhisp needs microphone access for speech-to-text dictation.</string>
</dict>
</plist>
PLIST

# Signing.
#   CODESIGN_IDENTITY unset or "-"  -> ad-hoc (default; fast local dev loop).
#   CODESIGN_IDENTITY="Developer ID Application: ..." -> real signing with the
#       hardened runtime + entitlements, which is what notarization requires.
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
ENTITLEMENTS="$ROOT/scripts/YOLOWhisp.entitlements"

if [[ "$CODESIGN_IDENTITY" == "-" ]]; then
  # Ad-hoc keeps a stable local identity for the keystroke/CGEvent and
  # Accessibility APIs. macOS may re-prompt for Accessibility after a rebuild;
  # the fixed bundle path minimises that.
  echo "==> Ad-hoc code signing..."
  codesign --force --deep --sign - "$APP_DIR"
else
  echo "==> Signing with: $CODESIGN_IDENTITY (hardened runtime)..."
  # No --deep: the bundle has a single Mach-O and no nested code, and Apple
  # advises against --deep for anything bound for notarization.
  codesign --force --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$CODESIGN_IDENTITY" "$APP_DIR"
  codesign --verify --strict --verbose=2 "$APP_DIR"
fi

echo "==> Done: $APP_DIR"
echo "    Run it with:  open \"$APP_DIR\"   (or: make run)"
