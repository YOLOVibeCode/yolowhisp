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
BUNDLE_ID="com.yolovibecode.yolowhisp"

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

# Ad-hoc sign so the bundle has a stable identity for the keystroke/CGEvent and
# Accessibility APIs. macOS may re-prompt for Accessibility after a rebuild;
# keeping the bundle at this fixed path minimises that.
echo "==> Ad-hoc code signing..."
codesign --force --deep --sign - "$APP_DIR"

echo "==> Done: $APP_DIR"
echo "    Run it with:  open \"$APP_DIR\"   (or: make run)"
