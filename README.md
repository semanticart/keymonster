# Key Monster

A lightweight clipboard history manager for macOS. Key Monster lives in your menu
bar, quietly records what you copy, and lets you search back through it and paste
any earlier entry from a fast, keyboard-driven panel.

## Features

- **Menu bar resident** — runs as a background accessory (`LSUIElement`), no Dock
  icon, no window cluttering your screen.
- **Captures text, images, and files** — records plain text, images (e.g. copied
  from Preview or a browser), and file URLs (files copied in Finder).
- **Search-first history panel** — a floating, centered panel with a search field
  that matches across text content, file names, and the source app name.
- **Fully keyboard-driven** — open with a global shortcut, type to filter, and
  navigate without touching the mouse:
  - `↑` / `↓` or `Ctrl-P` / `Ctrl-N` — move the selection
  - `Return` — paste the highlighted item into the app you were just using
    (or copy it, if auto-paste is off or unavailable)
  - `Esc` — dismiss the panel (it also closes when it loses focus)
- **Auto-paste** — `Return` pastes the selection straight into the previously
  focused app by synthesizing a `⌘V`, so you don't have to switch back and paste
  manually. On by default; it needs Accessibility permission (Key Monster requests
  it when you enable the toggle) and gracefully falls back to copy-only without it.
- **Source app tracking** — each entry remembers (and shows the icon of) the app
  it was copied from. The origin is preserved when you re-select an old item.
- **Configurable global shortcut** — record any modifier + key combo in Settings
  to summon the panel from anywhere.
- **App focus shortcuts** — bind a global shortcut to one or more apps. Press it
  to focus the app; press again while one is frontmost to cycle through the rest,
  so a single combo can rotate through e.g. Slack and Chrome. Settings warns when
  a combo is bound more than once, since only the first binding can register.
- **Password-manager aware** — respects the
  [nspasteboard.org](http://nspasteboard.org) convention and skips clipboard
  contents marked concealed, transient, or auto-generated.
- **Persistent & deduplicated** — history is stored locally in SQLite and
  survives restarts. Duplicate copies move to the top instead of piling up; the
  store is capped at 10,000 items.

## Requirements

- macOS 14 (Sonoma) or later
- Swift 6 toolchain (Xcode 16+) to build
- [SwiftLint](https://github.com/realm/SwiftLint) for `make lint`

## Building & Running

The project uses a `Makefile` for common tasks:

```sh
make run     # build a proper .app bundle (icon, menu bar agent, signed) and open it
make app     # build the .app bundle without launching it
make build   # plain `swift build`
make test    # run the test suite
make lint    # run SwiftLint
make clean   # clean build artifacts
```

`make run` assembles a real `.app` bundle so the menu bar agent, icon, and code
signature are in place. Because persistence is SQLite (via
[GRDB](https://github.com/groue/GRDB.swift)) rather than something requiring a
bundle identifier, plain `swift run` also works for day-to-day development.

Accessibility grants (needed for auto-paste) are tied to the app's code-signing
identity. The `Makefile` auto-detects a real signing identity from your keychain
and signs with it, so the grant persists across rebuilds; it falls back to ad-hoc
signing if none is found (in which case macOS forgets the grant on every rebuild).
Override explicitly with `make run CODESIGN_IDENTITY=<identity>` if needed.

## Usage

1. Launch Key Monster — a clipboard icon (`doc.on.clipboard`) appears in the menu bar.
   On first launch the Settings window opens automatically.
2. Record a **Global Shortcut**. To use auto-paste, leave **Paste into the active
   app on Return** enabled and grant **Accessibility** access when prompted
   (Key Monster links you to the right System Settings pane).
3. Copy things as you normally would; Key Monster records them in the background.
4. Press your shortcut (or choose **Show History** from the menu) to open the
   panel, type to search, select an entry, and press `Return` — it pastes into
   the app you came from (or just copies, if auto-paste is off/ungranted).

Your history is stored at:

```
~/Library/Application Support/keymonster/history.sqlite
```

## Architecture

| File | Responsibility |
| --- | --- |
| `KeyMonsterApp.swift` | App entry point and `AppDelegate` — wires up the status item, watcher, panel, hotkey, and store. |
| `ClipboardWatcher.swift` | Polls `NSPasteboard` `changeCount` and reports new contents. |
| `ClipboardHistory.swift` | Observable history model with dedup and size cap; `ClipItem` / `ClipContent` types. |
| `ClipStore.swift` | `ClipStore` persistence protocol and the GRDB/SQLite implementation. |
| `HistoryViewModel.swift` | Drives the panel's search + keyboard selection. |
| `Panel.swift` | The floating panel window and its key-handling. |
| `MenuContent.swift` | SwiftUI content of the history panel. |
| `SettingsView.swift` | Settings UI — shortcut recorder, focus-shortcut editor, and the auto-paste toggle. |
| `AppSettings.swift` | Persisted settings, shortcut formatting, and focus-shortcut conflict detection. |
| `HotkeyManager.swift` | Registers/unregisters the global hotkeys (history panel + every focus shortcut). |
| `AppFocuser.swift` | Focuses (or cycles through) the apps bound to a focus shortcut. |
| `Paster.swift` | Accessibility trust check/request and `⌘V` synthesis for auto-paste. |

The persistence layer is kept behind the narrow `ClipStore` protocol so
`ClipboardHistory` can be tested against an in-memory SQLite store
(`SQLiteClipStore.inMemory()`). Tests live in `Tests/keymonsterTests/`.

## Tech Stack

- Swift 6 + SwiftUI + AppKit
- [GRDB](https://github.com/groue/GRDB.swift) for SQLite persistence
