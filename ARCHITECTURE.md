# Architecture

All paths are relative to `Sources/keymonster/`.

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
