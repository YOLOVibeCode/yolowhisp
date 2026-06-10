# YOLOWhisp dev tasks. `CONFIG=release make app` for an optimized bundle.
CONFIG ?= debug

# Developer ID identity used by `make app-signed` (override with SIGN_ID=...).
SIGN_ID ?= Developer ID Application: NoctuSoft, Inc. (N42FM5L5KD)

.PHONY: build test app app-signed complete run clean

build:
	swift build -c $(CONFIG)

test:
	swift test

app:
	./scripts/build-app.sh $(CONFIG)

# Build a Developer ID-signed, hardened-runtime bundle (needs the cert in your
# keychain). This is signed but not notarized — notarization happens in CI.
app-signed:
	CODESIGN_IDENTITY="$(SIGN_ID)" ./scripts/build-app.sh $(CONFIG)

# Self-contained build: static whisper-cli (from source) + a bundled model.
# Needs cmake. CODESIGN_IDENTITY="$(SIGN_ID)" make complete for a signed build.
complete:
	./scripts/build-complete-app.sh $(CONFIG)

# Build the bundle and launch it (menu-bar app — look for the icon up top).
# Uses app-signed so Developer ID signing is stable across rebuilds, keeping
# TCC accessibility permissions intact between dev iterations.
run: app-signed
	open build/YOLOWhisp.app

clean:
	swift package clean
	rm -rf build
