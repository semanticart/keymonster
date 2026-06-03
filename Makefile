.PHONY: build run test clean lint app

CONFIG ?= debug
APP_NAME := Clipborg
APP_DIR := .build/$(APP_NAME).app

build:
	swift build

# `make run` builds a proper .app bundle (icon, menu bar agent, code signature).
# Persistence is SQLite via GRDB and needs no bundle identifier, so `swift run`
# also works for day-to-day development.
app: build
	rm -rf "$(APP_DIR)"
	mkdir -p "$(APP_DIR)/Contents/MacOS"
	mkdir -p "$(APP_DIR)/Contents/Resources"
	cp ".build/$(CONFIG)/clipborg" "$(APP_DIR)/Contents/MacOS/clipborg"
	cp Resources/Info.plist "$(APP_DIR)/Contents/Info.plist"
	cp Resources/AppIcon.icns "$(APP_DIR)/Contents/Resources/AppIcon.icns"
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
