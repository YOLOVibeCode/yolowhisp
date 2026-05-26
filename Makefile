# YOLOWhisp dev tasks. `CONFIG=release make app` for an optimized bundle.
CONFIG ?= debug

# Developer ID identity used by `make app-signed` (override with SIGN_ID=...).
SIGN_ID ?= Developer ID Application: NoctuSoft, Inc. (N42FM5L5KD)

.PHONY: build test app app-signed run clean

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

# Build the bundle and launch it (menu-bar app — look for the icon up top).
run: app
	open build/YOLOWhisp.app

clean:
	swift package clean
	rm -rf build
