.PHONY: build run test clean lint app snapshot site-shots site-cast icon install dist

CONFIG ?= debug
APP_NAME := Key Monster
APP_DIR := .build/$(APP_NAME).app
INSTALL_DIR ?= /Applications

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
	swift build -c $(CONFIG)

# `make run` builds a proper .app bundle (icon, menu bar agent, code signature).
# Persistence is SQLite via GRDB and needs no bundle identifier, so `swift run`
# also works for day-to-day development.
app: build
	rm -rf "$(APP_DIR)"
	mkdir -p "$(APP_DIR)/Contents/MacOS"
	mkdir -p "$(APP_DIR)/Contents/Resources"
	cp ".build/$(CONFIG)/keymonster" "$(APP_DIR)/Contents/MacOS/keymonster"
	cp Resources/Info.plist "$(APP_DIR)/Contents/Info.plist"
	cp Resources/AppIcon.icns "$(APP_DIR)/Contents/Resources/AppIcon.icns"
	codesign --force --sign "$(CODESIGN_IDENTITY)" "$(APP_DIR)"
	@echo "Built $(APP_DIR) (signed with: $(CODESIGN_IDENTITY))"

run: app
	pkill -x keymonster || true
	open "$(APP_DIR)"

# Render the history panel headlessly against the real on-disk history and write
# one PNG per selection state. Override args, e.g. `make snapshot SNAP_ARGS="--out /tmp/shots --count 8"`.
SNAP_ARGS ?=
snapshot: build
	swift run keymonster snapshot $(SNAP_ARGS)

# Regenerate the website screenshots in docs/assets/shots. Renders the real
# panels against seeded demo content (never the on-disk clipboard history), in
# dark and light appearance — safe to publish.
site-shots: build
	swift run keymonster snapshot --demo --out docs/assets/shots

# Regenerate the website's hero screencast. Drives the real panels through a
# scripted demo (seeded content, never the on-disk history — safe to publish),
# captures frames headlessly, and encodes docs/assets/cast/hero.mp4 plus its
# poster. Requires ffmpeg (`brew install ffmpeg`).
CAST_FRAMES := .build/cast-frames
site-cast: build
	@command -v ffmpeg >/dev/null || { echo "ffmpeg not found: brew install ffmpeg"; exit 1; }
	rm -rf "$(CAST_FRAMES)"
	swift run keymonster screencast --out "$(CAST_FRAMES)"
	mkdir -p docs/assets/cast
	ffmpeg -y -loglevel error -framerate 30 -i "$(CAST_FRAMES)/frame-%05d.png" \
		-c:v libx264 -pix_fmt yuv420p -crf 24 -preset slow -movflags +faststart \
		docs/assets/cast/hero.mp4
	ffmpeg -y -loglevel error -i "$(CAST_FRAMES)/poster.png" -qscale:v 4 \
		docs/assets/cast/hero-poster.jpg
	@echo "Wrote docs/assets/cast/hero.mp4 and hero-poster.jpg"

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

# Package the release .app into a distributable zip in .build/dist/. This is what
# the GitHub Releases workflow uploads. VERSION defaults to the Info.plist value
# (CI overrides it with the git tag). ditto is used instead of `zip` so the
# archive preserves the bundle's symlinks and code signature intact.
DIST_DIR := .build/dist
VERSION ?= $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
DIST_ZIP := $(DIST_DIR)/KeyMonster-$(VERSION).zip
dist:
	$(MAKE) app CONFIG=release
	mkdir -p "$(DIST_DIR)"
	rm -f "$(DIST_ZIP)"
	ditto -c -k --keepParent "$(APP_DIR)" "$(DIST_ZIP)"
	@echo "Wrote $(DIST_ZIP)"

# Build a release app bundle and install it to /Applications, replacing any
# existing copy. Override the destination with `make install INSTALL_DIR=~/Applications`.
install:
	$(MAKE) app CONFIG=release
	pkill -x keymonster || true
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	cp -R "$(APP_DIR)" "$(INSTALL_DIR)/$(APP_NAME).app"
	@echo "Installed $(APP_NAME).app to $(INSTALL_DIR)"
