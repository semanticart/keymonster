.PHONY: build run test clean lint app snapshot site-shots site-cast site-cast-voiced icon install dist notarize release

CONFIG ?= debug
APP_NAME := Key Monster
APP_DIR := .build/$(APP_NAME).app
INSTALL_DIR ?= /Applications

# Accessibility (needed for auto-paste) grants are keyed to the app's code-signing
# identity. Ad-hoc signing ("-") produces a new identity on every rebuild, so the
# grant is lost each time and the app keeps asking for permission. If a real
# signing identity is in the keychain, use it: TCC then keys the grant to the
# cert + bundle id, so it persists across rebuilds. Falls back to ad-hoc otherwise.
# "Developer ID Application" wins over other identities: it's the only kind Apple
# accepts for notarization, and using it locally too means dev builds and the
# released app share one TCC grant.
# Override explicitly with `make run CODESIGN_IDENTITY=...` if needed.
CODESIGN_IDENTITY ?= $(shell security find-identity -v -p codesigning 2>/dev/null | awk 'match($$0, /[0-9A-F]{40}/) { id = substr($$0, RSTART, RLENGTH); if (!first) first = id; if (/Developer ID Application/) { devid = id; exit } } END { print (devid ? devid : first) }')
ifeq ($(strip $(CODESIGN_IDENTITY)),)
override CODESIGN_IDENTITY := -
endif

# Notarization requires the hardened runtime and a secure timestamp. Ad-hoc
# signatures can't carry a trusted timestamp, so these flags only apply when a
# real identity is used. The app needs no entitlement exceptions: Accessibility
# and the event tap are TCC grants, not hardened-runtime entitlements.
ifeq ($(CODESIGN_IDENTITY),-)
CODESIGN_FLAGS :=
else
CODESIGN_FLAGS := --options runtime --timestamp
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
	codesign --force $(CODESIGN_FLAGS) --sign "$(CODESIGN_IDENTITY)" "$(APP_DIR)"
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

# Narrated variant of the hero screencast: synthesizes a voiceover from
# scripts/cast-narration.txt with the best installed macOS voice, re-records
# the screencast with each scene sized to its line, and muxes
# docs/assets/cast/hero-voiced.mp4. The silent hero.mp4 stays untouched.
site-cast-voiced: build
	scripts/voice-cast.sh

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

# Package the release .app into a distributable DMG in .build/dist/. This is what
# the GitHub Releases workflow uploads. VERSION defaults to the Info.plist value
# (CI overrides it with the git tag). The volume gets an /Applications symlink for
# the usual drag-to-install layout, and the DMG itself is signed when a real
# identity is available so it can be notarized (see `make notarize`).
DIST_DIR := .build/dist
VERSION ?= $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
DIST_DMG := $(DIST_DIR)/KeyMonster-$(VERSION).dmg
DMG_STAGING := $(DIST_DIR)/dmg-staging
dist:
	$(MAKE) app CONFIG=release
	mkdir -p "$(DIST_DIR)"
	rm -rf "$(DMG_STAGING)" "$(DIST_DMG)"
	mkdir -p "$(DMG_STAGING)"
	cp -R "$(APP_DIR)" "$(DMG_STAGING)/$(APP_NAME).app"
	ln -s /Applications "$(DMG_STAGING)/Applications"
	hdiutil create -volname "$(APP_NAME)" -srcfolder "$(DMG_STAGING)" -ov -format UDZO "$(DIST_DMG)"
	rm -rf "$(DMG_STAGING)"
ifneq ($(CODESIGN_IDENTITY),-)
	codesign --timestamp --sign "$(CODESIGN_IDENTITY)" "$(DIST_DMG)"
endif
	@echo "Wrote $(DIST_DMG)"

# Submit the DMG to Apple's notary service and staple the ticket so Gatekeeper
# accepts it offline, then verify the result. Locally this uses the
# `keymonster-notary` keychain profile (see README); CI overrides NOTARY_ARGS
# with --apple-id/--team-id/--password flags whose values come from repo
# secrets. CI passes them as $$-escaped variable *references*, so the echoed
# recipe shows names, never values — keep this recipe un-@-silenced.
NOTARY_ARGS ?= --keychain-profile keymonster-notary
notarize:
	xcrun notarytool submit "$(DIST_DMG)" $(NOTARY_ARGS) --wait
	xcrun stapler staple "$(DIST_DMG)"
	spctl -a -t open --context context:primary-signature -vv "$(DIST_DMG)"

# Cut a release: stamp VERSION into Info.plist, commit that one file, tag
# vVERSION, and push both — the GitHub Release workflow does the rest (build,
# sign, notarize, publish). Run as `make release VERSION=x.y.z` from main.
# The commit is path-limited to Info.plist, so an otherwise dirty tree is fine.
release:
	@test "$$(git branch --show-current)" = main || \
		{ echo "release must be cut from main (currently on $$(git branch --show-current))"; exit 1; }
	@current=$$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist); \
		test "$(VERSION)" != "$$current" || \
		{ echo "VERSION=$(VERSION) is already the current version; pass the new one, e.g. make release VERSION=x.y.z"; exit 1; }
	@echo "$(VERSION)" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$$' || \
		{ echo "VERSION must look like x.y.z (got '$(VERSION)')"; exit 1; }
	@! git rev-parse -q --verify "refs/tags/v$(VERSION)" >/dev/null || \
		{ echo "tag v$(VERSION) already exists"; exit 1; }
	@git diff --quiet Resources/Info.plist || \
		{ echo "Resources/Info.plist already has uncommitted changes; commit or revert them first"; exit 1; }
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" Resources/Info.plist
	git commit -m "Release $(VERSION)" Resources/Info.plist
	git tag "v$(VERSION)"
	git push origin main "v$(VERSION)"
	@echo "Tagged v$(VERSION) — the Release workflow builds and publishes it from here."

# Build a release app bundle and install it to /Applications, replacing any
# existing copy. Override the destination with `make install INSTALL_DIR=~/Applications`.
install:
	$(MAKE) app CONFIG=release
	pkill -x keymonster || true
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	cp -R "$(APP_DIR)" "$(INSTALL_DIR)/$(APP_NAME).app"
	@echo "Installed $(APP_NAME).app to $(INSTALL_DIR)"
