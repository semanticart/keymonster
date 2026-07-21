# Key Monster

A keyboard-driven macOS utility built around your clipboard. Key Monster lives in
the menu bar, quietly records what you copy, and lets you search back through it
and paste any earlier entry from a fast, centered panel — plus a set of
keyboard-only ways to drive the rest of your Mac: focus apps, click anything on
screen, and jump the caret through text, all without the mouse.

## Features

### Clipboard history

- **Menu bar resident** — runs as a background accessory (`LSUIElement`), no Dock
  icon, no window cluttering your screen.
- **Captures text, images, and files** — records plain text, images (e.g. copied
  from Preview or a browser), and file URLs (files copied in Finder).
- **Search-first, two-pane panel** — a floating, centered panel with a search
  field that matches across text content, file names, and the source app name.
  The left column lists matches; the right column previews the full content of the
  selected item — the complete text, the image, or every file path.
- **Fully keyboard-driven** — open with a global shortcut, type to filter, and
  navigate without touching the mouse:
  - `↑` / `↓` or `Ctrl-N` / `Ctrl-P` — move the selection
  - `Ctrl-J` / `Ctrl-K` — scroll the preview pane for long content
  - `Return` — paste the highlighted item into the app you were just using
    (or copy it, if auto-paste is off or unavailable)
  - `Esc` — dismiss the panel (it also closes when it loses focus)
- **Auto-paste** — `Return` pastes the selection straight into the previously
  focused app by synthesizing a `⌘V`, so you don't have to switch back and paste
  manually. On by default; it needs Accessibility permission (Key Monster requests
  it when you enable the toggle) and gracefully falls back to copy-only without it.
- **Source app tracking** — each entry remembers (and shows the icon of) the app
  it was copied from. The origin is preserved when you re-select an old item.
- **Password-manager aware** — respects the
  [nspasteboard.org](http://nspasteboard.org) convention and skips clipboard
  contents marked concealed, transient, or auto-generated.
- **Persistent & deduplicated** — history is stored locally in SQLite and
  survives restarts. Duplicate copies move to the top instead of piling up; the
  store is capped at 10,000 items.

### Keyboard shortcuts for the rest of your Mac

- **Configurable global shortcut** — record any modifier + key combo in Settings
  to summon the history panel from anywhere.
- **App focus shortcuts** — bind a global shortcut to one or more apps. Press it
  to focus the app; press again while one is frontmost to cycle through the rest,
  so a single combo can rotate through e.g. Slack and Chrome. Settings warns when
  a combo is bound more than once, since only the first binding can register.
- **Click hints (vimium-style)** — press a shortcut and every clickable element
  in the frontmost window grows a short label (a single home-row letter when
  few elements are visible, two letters otherwise); type a label to click it
  without touching the mouse. Works on native macOS
  controls and on web content in Safari, Chrome, and Electron apps (Key Monster
  asks them to expose their accessibility trees). Separate shortcuts for
  left-click and right-click hints; holding `Shift` on the final letter clicks
  with the opposite button. Elements too close together to label individually
  share one green area label — typing it zooms into that area (a magnified
  screenshot with Screen Recording permission, sketched outlines without) and
  each element gets a normal label; `Delete` backs out of the zoom. `Esc`, a
  real click, or any other chord dismisses the overlay. Requires Accessibility
  permission.
- **Grid click** — for clicking somewhere with no element to label, a shortcut
  overlays a fine grid on the frontmost window, each cell wearing a short
  home-row label; type the label nearest your target to pick a starting cell.
  From there the grid mirrors the keyboard's three letter rows (`Q`…`\`,
  `A`…`'`, `Z`…`/`), so the key under your finger names the cell in the same spot
  on screen — and each keypress zooms into that cell, magnifying it into a loupe
  so small targets stay legible. After a few zooms the next key clicks its cell.
  `Return` clicks the center of the current region at any point, and holding
  `Shift` on the deciding key right-clicks instead. `Delete` zooms back out (and
  from the first zoom, back to the initial label grid); `Esc`, a real click, or
  any other chord dismisses. Requires Accessibility permission.
- **Text jump (jump to character)** — press a shortcut while a text field is
  focused, then any character; every visible occurrence of it in the field grows
  a short label (one letter when there are only a few, two otherwise), and typing
  a label drops the caret just before that character. Matching is case-insensitive and works on digits, punctuation, and
  spaces too. Occurrences too close together share one green area label that
  zooms in, just like click hints. Works in native macOS fields and in web text
  areas (Safari, Chrome, Electron). `Delete` backs out of the zoom, then back to
  pick a different character; `Esc`, a real click, or any other chord dismisses.
  Requires Accessibility permission.
- **Menu search** — press a shortcut to list the frontmost app's entire menu bar
  in a searchable panel. Type to fuzzy-find across the whole menu path (so `exp
pdf` reaches **File › Export › PDF…**); the closest match floats to the top.
  Navigate with `↑` / `↓` or `Ctrl-N` / `Ctrl-P`, and press `Return` to run the
  highlighted item back in that app — no reaching for the mouse to hunt through
  menus. `Esc` cancels. Disabled items and separators are skipped. Requires
  Accessibility permission.
- **Script shortcuts** — point a global shortcut at any script file on disk and
  press it to run the script in the background — toggle dark mode, start a
  timer, rearrange windows, whatever you can script. Pick the file with a
  chooser or drag it from Finder onto the Scripts tab — onto a row to change
  that row's script, or onto **Add Script** to create shortcuts for the
  dropped files. How it runs is inferred
  from the file: AppleScript (`.scpt`, `.scptd`, `.applescript`) runs via
  `osascript`, executable files run directly (their shebang picks the
  interpreter), and anything else runs in `zsh` as a login shell, so your usual
  `PATH` applies. Failures (non-zero exits, with stderr) are appended to
  `~/Library/Logs/keymonster/scripts.log`; the Scripts settings tab shows the
  latest failure with an **Open Log** button, and everything is also logged
  under the `keymonster` subsystem in Console.

### Convenience

- **Launch at login** — an optional toggle registers Key Monster to start
  automatically when you log in.

## Download

Grab the latest `KeyMonster-<version>.zip` from the
[Releases](../../releases/latest) page, unzip it, and drag **Key Monster.app**
into `/Applications`.

The released build is signed ad-hoc rather than notarized with an Apple Developer
ID, so the first launch trips Gatekeeper. Either right-click the app and choose
**Open** (then confirm), or clear the quarantine flag once from a terminal:

```sh
xattr -dr com.apple.quarantine "/Applications/Key Monster.app"
```

Prefer to build it yourself? See [Building & Running](#building--running) below.

## Requirements

- macOS 14 (Sonoma) or later
- Swift 6 toolchain (Xcode 16+) to build
- [SwiftLint](https://github.com/realm/SwiftLint) for `make lint`

## Building & Running

The project uses a `Makefile` for common tasks:

```sh
make run      # build a proper .app bundle (icon, menu bar agent, signed) and open it
make app      # build the .app bundle without launching it
make build    # plain `swift build`
make install  # build a release bundle and copy it into /Applications
make test     # run the test suite
make lint     # run SwiftLint
make icon     # regenerate Resources/AppIcon.icns from Resources/icon.svg
make dist     # build the release .app and zip it into .build/dist/ for distribution
make clean    # clean build artifacts
```

`make run` assembles a real `.app` bundle so the menu bar agent, icon, and code
signature are in place. Because persistence is SQLite (via
[GRDB](https://github.com/groue/GRDB.swift)) rather than something requiring a
bundle identifier, plain `swift run` also works for day-to-day development.
`make install` builds a release bundle and installs it to `/Applications`
(override with `make install INSTALL_DIR=~/Applications`).

### Cutting a release

Releases are published by GitHub Actions
([`.github/workflows/release.yml`](.github/workflows/release.yml)). Push a
version tag and the workflow builds the release `.app`, stamps the tag into the
bundle version, zips it with `make dist`, and attaches it to a GitHub Release
with auto-generated notes:

```sh
git tag v0.1.0
git push origin v0.1.0
```

Keep the tag in sync with `CFBundleShortVersionString` in `Resources/Info.plist`.
You can also trigger the workflow manually from the **Actions** tab, passing the
tag to cut.

Accessibility grants (needed for auto-paste, click hints, grid click, and text
jump) are tied to the app's code-signing identity. The `Makefile` auto-detects a
real signing identity from your keychain and signs with it, so the grant persists
across rebuilds; it falls back to ad-hoc signing if none is found (in which case
macOS forgets the grant on every rebuild). Override explicitly with
`make run CODESIGN_IDENTITY=<identity>` if needed.

## Usage

1. Launch Key Monster — the monster-keyboard glyph appears in the menu bar.
   On first launch the Settings window opens automatically.
2. Settings is organized into tabs, one per feature, each with a short
   description of what it does. In the **Clipboard** tab, record a **Clipboard
   Shortcut**. To use auto-paste, leave **Paste into the active app on Return**
   enabled and grant **Accessibility** access when prompted (Key Monster links
   you to the right System Settings pane).
3. Optionally set up the other tabs — **Focus** (app switching), **Clicking**
   (hints and grid), **Text** (jump to character), **Menus** (menu search), and
   **Scripts** (run script files) — and toggle **Launch at Login** in the
   **General** tab, which leads the row.
4. Copy things as you normally would; Key Monster records them in the background.
5. Press your shortcut (or choose **Show Clipboard History** from the menu) to open the
   panel, type to search, select an entry, and press `Return` — it pastes into
   the app you came from (or just copies, if auto-paste is off/ungranted).

Your history is stored at:

```
~/Library/Application Support/keymonster/history.sqlite
```

## Architecture

| File                                    | Responsibility                                                                                                                                                  |
| --------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `KeyMonsterApp.swift`                   | App entry point and `AppDelegate` — wires up the status item, watcher, panel, hotkeys, and store. Also routes the `snapshot` argument to the headless renderer. |
| `ClipboardWatcher.swift`                | Polls `NSPasteboard` `changeCount` and reports new contents.                                                                                                    |
| `ClipboardHistory.swift`                | Observable history model with search matching, dedup, and size cap; `ClipItem` / `ClipContent` types (headless — no AppKit).                                    |
| `ClipboardHistory+AppKit.swift`         | The model's AppKit edge: pasteboard writer, app-icon lookup, `NSRunningApplication` convenience.                                                                |
| `ClipStore.swift`                       | `ClipStore` persistence protocol and the GRDB/SQLite implementation.                                                                                            |
| `HistoryViewModel.swift`                | Drives the panel's search, keyboard selection, and preview-pane scrolling.                                                                                      |
| `Panel.swift`                           | The floating panel window; `PanelCommand` maps its keys to actions.                                                                                             |
| `MenuContent.swift`                     | SwiftUI content of the history panel: header, search, list + detail split, footer.                                                                              |
| `DetailPanel.swift`                     | The right-hand preview pane that shows the selected item's full content.                                                                                        |
| `AppIconView.swift`                     | Draws the full-color app icon in code (from `icon.svg`'s geometry) for in-app and headless use.                                                                 |
| `MenuBarIcon.swift`                     | Draws the monochrome template glyph shown in the menu bar.                                                                                                      |
| `UIScale.swift`                         | The single scale factor applied to the panel and its contents.                                                                                                  |
| `Snapshot.swift`                        | Headless renderer (`keymonster snapshot`) that writes PNGs of the panel for design iteration.                                                                   |
| `SettingsView.swift`                    | Tabbed Settings UI — one tab per feature (General, Clipboard, Focus, Clicking, Text, Menus, Scripts), each with a description.                                   |
| `ShortcutControls.swift`                | Reusable Settings pieces: the shortcut recorder, conflict/Accessibility notices, the grouped section card, and the standard row shapes.                         |
| `ScriptSettingsView.swift`              | The Scripts tab's rows (shortcut + script-file picker) and the last-failure notice with its Open Log button.                                                    |
| `AppSettings.swift`                     | Persisted settings, shortcut formatting, launch-at-login registration, and conflict detection.                                                                  |
| `HotkeyManager.swift`                   | Registers/unregisters the global hotkeys (history panel, focus, hint, grid, text-jump, menu-search, and script shortcuts).                                      |
| `AppFocuser.swift`                      | Focuses (or cycles through) the apps bound to a focus shortcut.                                                                                                 |
| `ScriptRunner.swift`                    | `ScriptShortcut` model, the pure script-file→process mapping (`ScriptInvocation`), and the background `Process` launcher.                                       |
| `ScriptLog.swift`                       | Appends script failures to `~/Library/Logs/keymonster/scripts.log` and publishes the latest one for the Scripts tab.                                            |
| `Paster.swift`                          | Accessibility trust check/request and `⌘V` synthesis for auto-paste.                                                                                            |
| `Hints/HintModeController.swift`        | Orchestrates hint mode: scan → overlay → keystrokes → click.                                                                                                    |
| `Hints/GridModeController.swift`        | Orchestrates grid mode: initial label grid → pick a cell → keyboard-position grid, zoom per keystroke → click.                                                  |
| `Hints/GridHints.swift`                 | Pure geometry for the initial grid: a fine, evenly tiled grid whose cells carry two-character home-row labels for the first pick.                               |
| `Hints/GridDivision.swift`              | Pure geometry that splits a rect into keyboard-mirroring grid cells.                                                                                            |
| `Hints/GridZoom.swift`                  | Pure geometry for the grid loupe: how far the active region magnifies to fill the window, and where it draws.                                                   |
| `Hints/GridOverlay.swift`               | Transparent overlay that dims the surroundings and draws the grid's cells and key badges.                                                                       |
| `Hints/LabelSession.swift`              | The labeling/zoom state machine shared by hint mode and text jump: group, type, zoom, commit.                                                                   |
| `Hints/BadgeMetrics.swift`              | Badge font and box metrics, shared by grouping and the overlay view.                                                                                            |
| `Hints/HintLabels.swift`                | Two-letter label generation (home row first) and the typed-prefix state machine.                                                                                |
| `Hints/HintTargets.swift`               | Pure clickability/visibility heuristics and AX↔Cocoa coordinate conversion.                                                                                     |
| `Hints/HintScreens.swift`               | Finds the screen a target window sits on, so labels can hang just outside window edges.                                                                         |
| `Hints/AXHintTargetFinder.swift`        | Walks the frontmost window's accessibility tree to find clickable elements.                                                                                     |
| `Hints/HintOverlay.swift`               | Transparent click-through window that draws the hint badges and the zoom panel.                                                                                 |
| `Hints/HintGrouping.swift`              | Merges targets whose labels would collide into green area groups.                                                                                               |
| `Hints/HintZoom.swift`                  | Geometry of the zoomed view: panel placement, magnification, label spots.                                                                                       |
| `Hints/WindowCapture.swift`             | Screenshots the region beneath the overlay for the zoomed view.                                                                                                 |
| `Hints/HintKeyTap.swift`                | CGEvent tap that captures keystrokes while hints or the grid are showing.                                                                                       |
| `Hints/MouseClicker.swift`              | Synthesizes left/right clicks at a target's center.                                                                                                             |
| `Hints/TextJumpController.swift`        | Orchestrates text-jump mode: arm → pick character → label occurrences → place caret.                                                                            |
| `Hints/AXFocusedText.swift`             | Reads the focused text field's value/caret via AX, finds a character's on-screen occurrences, and moves the caret.                                              |
| `MenuFinder/MenuBarItem.swift`          | The `MenuBarItem` value type plus the pure fuzzy matcher (`FuzzyMatch`) and ranked filter (`MenuItemFilter`) — no AppKit, fully tested.                         |
| `MenuFinder/AXMenuBarScanner.swift`     | Walks the frontmost app's menu bar via AX into actionable leaf items (with the `AXUIElement` to press for each), and presses the chosen one.                    |
| `MenuFinder/MenuFinderViewModel.swift`  | Drives the menu-finder panel's search, keyboard selection, and activation.                                                                                      |
| `MenuFinder/MenuFinderController.swift` | The floating menu-finder panel; `MenuFinderCommand` maps its keys to actions. Scans on show, presses the item back into the prior app on Return.                |
| `MenuFinder/MenuFinderContent.swift`    | SwiftUI content of the menu-finder panel: header, search, and the ranked single-column list.                                                                    |
| `AppPicker.swift`                       | AppKit bridges for choosing an app and fetching its icon, used by the focus-shortcut editor.                                                                    |

The persistence layer is kept behind the narrow `ClipStore` protocol so
`ClipboardHistory` can be tested against an in-memory SQLite store
(`SQLiteClipStore.inMemory()`). Tests live in `Tests/keymonsterTests/`.

## Tech Stack

- Swift 6 + SwiftUI + AppKit
- [GRDB](https://github.com/groue/GRDB.swift) for SQLite persistence
