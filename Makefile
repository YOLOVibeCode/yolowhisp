# YOLOWhisp dev tasks. `CONFIG=release make app` for an optimized bundle.
CONFIG ?= debug

.PHONY: build test app run clean

build:
	swift build -c $(CONFIG)

test:
	swift test

app:
	./scripts/build-app.sh $(CONFIG)

# Build the bundle and launch it (menu-bar app — look for the icon up top).
run: app
	open build/YOLOWhisp.app

clean:
	swift package clean
	rm -rf build
