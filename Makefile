.PHONY: build run test clean lint app snapshot icon

CONFIG ?= debug
APP_NAME := Clipborg
APP_DIR := .build/$(APP_NAME).app

# Accessibility (needed for auto-paste) grants are keyed to the app's code-signing
# identity. Ad-hoc signing ("-") produces a new identity on every rebuild, so the
# grant is lost each time and the app keeps asking for permission. If a real
# signing identity is in the keychain, use it: TCC then keys the grant to the
# cert + bundle id, so it persists across rebuilds. Falls back to ad-hoc otherwise.
# Override explicitly with `make run CODESIGN_IDENTITY=...` if needed.
CODESIGN_IDENTITY ?= $(shell security find-identity -v -p codesigning 2>/dev/null | awk 'match($$0, /[0-9A-F]{40}/) {print substr($$0, RSTART, RLENGTH); exit}')
ifeq ($(strip $(CODESIGN_IDENTITY)),)
override CODESIGN_IDENTITY := -
endif

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
	codesign --force --sign "$(CODESIGN_IDENTITY)" "$(APP_DIR)"
	@echo "Built $(APP_DIR) (signed with: $(CODESIGN_IDENTITY))"

run: app
	-pkill -x clipborg
	open "$(APP_DIR)"

# Render the history panel headlessly against the real on-disk history and write
# one PNG per selection state. Override args, e.g. `make snapshot SNAP_ARGS="--out /tmp/shots --count 8"`.
SNAP_ARGS ?=
snapshot: build
	swift run clipborg snapshot $(SNAP_ARGS)

# Regenerate Resources/AppIcon.icns from Resources/icon.svg. Edit the SVG, then
# run this to rebuild the bundled icon at every size macOS needs. Requires
# rsvg-convert (`brew install librsvg`) and iconutil (ships with macOS).
ICONSET := .build/AppIcon.iconset
icon:
	@command -v rsvg-convert >/dev/null || { echo "rsvg-convert not found: brew install librsvg"; exit 1; }
	rm -rf "$(ICONSET)"
	mkdir -p "$(ICONSET)"
	rsvg-convert -w 16   -h 16   Resources/icon.svg -o "$(ICONSET)/icon_16x16.png"
	rsvg-convert -w 32   -h 32   Resources/icon.svg -o "$(ICONSET)/icon_16x16@2x.png"
	rsvg-convert -w 32   -h 32   Resources/icon.svg -o "$(ICONSET)/icon_32x32.png"
	rsvg-convert -w 64   -h 64   Resources/icon.svg -o "$(ICONSET)/icon_32x32@2x.png"
	rsvg-convert -w 128  -h 128  Resources/icon.svg -o "$(ICONSET)/icon_128x128.png"
	rsvg-convert -w 256  -h 256  Resources/icon.svg -o "$(ICONSET)/icon_128x128@2x.png"
	rsvg-convert -w 256  -h 256  Resources/icon.svg -o "$(ICONSET)/icon_256x256.png"
	rsvg-convert -w 512  -h 512  Resources/icon.svg -o "$(ICONSET)/icon_256x256@2x.png"
	rsvg-convert -w 512  -h 512  Resources/icon.svg -o "$(ICONSET)/icon_512x512.png"
	rsvg-convert -w 1024 -h 1024 Resources/icon.svg -o "$(ICONSET)/icon_512x512@2x.png"
	iconutil -c icns "$(ICONSET)" -o Resources/AppIcon.icns
	rm -rf "$(ICONSET)"
	@echo "Wrote Resources/AppIcon.icns from Resources/icon.svg"

test:
	swift test

clean:
	swift package clean
	rm -rf "$(APP_DIR)"

lint:
	swiftlint lint
