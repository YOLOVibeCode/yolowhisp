#!/usr/bin/env bash
#
# Assemble a SELF-CONTAINED YOLOWhisp.app: a whisper-cli built from source with
# backends STATICALLY linked (no dlopen'd .so's, Metal shader embedded) plus a
# bundled model — so a fresh user needs nothing external. Apple-Silicon only.
#
# Why from source: Homebrew's whisper-cli loads ggml backends by scanning a
# compiled-in absolute path and can't be redirected to a bundle, so copying its
# dylibs doesn't work. A static build sidesteps that entirely.
#
# Usage:
#   [CODESIGN_IDENTITY="Developer ID Application: ..."] [MODEL=base] [WHISPER_REF=v1.8.4] \
#     ./scripts/build-complete-app.sh [debug|release]
#
set -euo pipefail

CONFIG="${1:-release}"
APP_NAME="YOLOWhisp"
BUNDLE_ID="com.noctusoft.yolowhisp"
SIGN_IDENTITY="${CODESIGN_IDENTITY:--}"   # default ad-hoc for local testing
# Bundle the model the app defaults to (`large-v3-turbo`) so a fresh install
# runs at full accuracy out of the box. Override with MODEL=base for a much
# smaller (~150MB vs ~1.6GB) bundle that falls back gracefully.
MODEL="${MODEL:-large-v3-turbo}"
WHISPER_REF="${WHISPER_REF:-v1.8.4}"      # matches Homebrew's whisper-cpp 1.8.4
MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-${MODEL}.bin"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
VERSION="$(git describe --tags --always 2>/dev/null || echo dev)"
ENT="$ROOT/scripts/YOLOWhisp.entitlements"

command -v cmake >/dev/null || { echo "error: cmake required (brew install cmake)" >&2; exit 1; }

echo "==> Building app ($CONFIG)..."
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/$APP_NAME"

# ---- build a static, self-contained whisper-cli from source ----
WSRC="$ROOT/build/whisper-src"
if [[ ! -d "$WSRC/.git" ]]; then
  rm -rf "$WSRC"
  git clone --depth 1 --branch "$WHISPER_REF" https://github.com/ggerganov/whisper.cpp "$WSRC"
fi
echo "==> Building whisper-cli from source ($WHISPER_REF, static + embedded Metal)..."
cmake -S "$WSRC" -B "$WSRC/cmbuild" \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DBUILD_SHARED_LIBS=OFF -DGGML_BACKEND_DL=OFF \
  -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON \
  -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_SERVER=OFF >/dev/null
cmake --build "$WSRC/cmbuild" --config Release --target whisper-cli -j >/dev/null
WHISPER_CLI="$(find "$WSRC/cmbuild" -name whisper-cli -type f -perm +111 | head -1)"
[[ -x "$WHISPER_CLI" ]] || { echo "error: whisper-cli not built" >&2; exit 1; }
echo "==> built $WHISPER_CLI"
echo "    deps:"; otool -L "$WHISPER_CLI" | sed 's/^/      /'

# ---- assemble the app ----
APP="$ROOT/build/$APP_NAME-complete.app"
C="$APP/Contents"
rm -rf "$APP"
mkdir -p "$C/MacOS" "$C/Resources/whisper/bin" "$C/Resources/whisper/models"
cp "$BIN" "$C/MacOS/$APP_NAME"
BUNDLE_SRC="$(dirname "$BIN")/${APP_NAME}_${APP_NAME}.bundle"
[[ -d "$BUNDLE_SRC" ]] && cp -R "$BUNDLE_SRC" "$C/Resources/"
cp "$WHISPER_CLI" "$C/Resources/whisper/bin/whisper-cli"

cat > "$C/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>YOLOWhisp needs microphone access for speech-to-text dictation.</string>
</dict>
</plist>
PLIST

LOCAL_MODEL="$HOME/.local/share/whisper/ggml-${MODEL}.bin"
if [[ -f "$LOCAL_MODEL" ]]; then
  echo "==> Using local model $LOCAL_MODEL"
  cp "$LOCAL_MODEL" "$C/Resources/whisper/models/ggml-${MODEL}.bin"
else
  echo "==> Downloading model ggml-${MODEL}.bin..."
  curl -fL -o "$C/Resources/whisper/models/ggml-${MODEL}.bin" "$MODEL_URL"
fi

echo "==> Verifying whisper-cli has no Homebrew dependencies..."
if otool -L "$C/Resources/whisper/bin/whisper-cli" | grep -q "/opt/homebrew"; then
  echo "ERROR: bundled whisper-cli still links Homebrew libs:" >&2
  otool -L "$C/Resources/whisper/bin/whisper-cli" | grep "/opt/homebrew" >&2
  exit 1
fi

# ---- sign ----
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  echo "==> Ad-hoc signing (local)..."
  codesign --force --sign - "$C/Resources/whisper/bin/whisper-cli"
  codesign --force --deep --sign - "$APP"
else
  echo "==> Signing with $SIGN_IDENTITY (hardened runtime)..."
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$C/Resources/whisper/bin/whisper-cli"
  codesign --force --options runtime --timestamp --entitlements "$ENT" --sign "$SIGN_IDENTITY" "$C/MacOS/$APP_NAME"
  codesign --force --options runtime --timestamp --entitlements "$ENT" --sign "$SIGN_IDENTITY" "$APP"
  codesign --verify --strict --verbose=2 "$APP"
fi

# ---- smoke test: the static binary must transcribe with no external deps ----
echo "==> Smoke test..."
SMOKE_ERR="$(mktemp)"
if "$C/Resources/whisper/bin/whisper-cli" \
     -m "$C/Resources/whisper/models/ggml-${MODEL}.bin" -f "$ROOT/benchmark/sample.wav" -l en -np \
     >/tmp/yws_smoke_out.txt 2>"$SMOKE_ERR"; then
  echo "    smoke OK ($(tr -d '\n' < /tmp/yws_smoke_out.txt | cut -c1-60)...)"
else
  echo "ERROR: bundled whisper-cli failed:" >&2; cat "$SMOKE_ERR" >&2; exit 1
fi
rm -f "$SMOKE_ERR"

echo "==> Done: $APP"
echo "    Self-contained (static whisper-cli + ggml-${MODEL}.bin). Run: open \"$APP\""
