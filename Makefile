.PHONY: build run test clean lint app

CONFIG ?= debug
APP_NAME := Clipborg
APP_DIR := .build/$(APP_NAME).app

build:
	swift build

# SwiftData requires a real bundle identifier, so the app must run from a
# proper .app bundle. The bare `swift run` executable has no bundle id and
# crashes inside SwiftData on the first save. Use `make run` (which builds
# and launches the bundle), not `swift run`, to run the app.
app: build
	rm -rf "$(APP_DIR)"
	mkdir -p "$(APP_DIR)/Contents/MacOS"
	cp ".build/$(CONFIG)/clipborg" "$(APP_DIR)/Contents/MacOS/clipborg"
	cp Resources/Info.plist "$(APP_DIR)/Contents/Info.plist"
	codesign --force --sign - "$(APP_DIR)"
	@echo "Built $(APP_DIR)"

run: app
	open "$(APP_DIR)"

test:
	swift test

clean:
	swift package clean
	rm -rf "$(APP_DIR)"

lint:
	swiftlint lint
