import AppKit

/// Shows hint badges in a transparent, click-through window covering the
/// screen the frontmost app's focused window is on — badges for elements at
/// the window's edge may hang just outside it.
@MainActor
final class HintOverlay {
    private var window: NSWindow?
    private var view: HintOverlayView?
    /// AX (top-left origin) coordinates of the overlay window's own origin —
    /// what to subtract to make a global AX rect view-local.
    private var origin: CGPoint = .zero

    /// `windowFrame` is the target window's frame in AX (top-left origin)
    /// coordinates — the same space the groups' frames are in. Single-member
    /// groups draw a normal badge; clusters draw a green area badge plus a
    /// translucent green wash over the area itself, so it's clear which
    /// targets the one label stands for.
    func show(groups: [HintGrouping.Group], labels: [String], windowFrame: CGRect) {
        guard let view = install(around: windowFrame) else { return }
        // Badge rects become view-local (the view is flipped, so it shares the
        // AX tree's top-left origin — only the overlay's origin needs removing).
        view.badges = zip(groups, labels).map { group, label in
            HintOverlayView.Badge(
                rect: group.badge.offsetBy(dx: -origin.x, dy: -origin.y),
                label: label,
                target: group.area.offsetBy(dx: -origin.x, dy: -origin.y),
                isGroup: group.isCluster,
                caret: HintOverlayView.caretDirection(from: group.badge, toward: group.area)
            )
        }
    }

    /// Shows a centered message over the window with no hints — used to signal
    /// that a mode is armed and waiting for input.
    func showBanner(_ text: String, windowFrame: CGRect) {
        install(around: windowFrame)?.banner = text
    }

    /// Outlines scroll mode's panes (AX coordinates, like `show`). A labeled
    /// pane is a pick candidate; a nil label marks the active pane being
    /// scrolled. `banner` is the mode's key legend, drawn low on the window.
    func showPanes(
        _ panes: [(rect: CGRect, label: String?)], windowFrame: CGRect, banner: String? = nil
    ) {
        guard let view = install(around: windowFrame) else { return }
        view.panes = panes.map {
            HintOverlayView.Pane(
                rect: $0.rect.offsetBy(dx: -origin.x, dy: -origin.y), label: $0.label
            )
        }
        view.bannerEdge = .bottom
        view.banner = banner
    }

    /// Magnifies `area` (AX coordinates) in a panel over the same window, with
    /// one normal badge per member frame. Screenshots what's beneath the
    /// overlay itself; callers gate on `WindowCapture.ensureAccess()`, so a
    /// nil image only means the capture itself failed. Call while the overlay
    /// is already showing; `clearZoom` restores the group badges untouched.
    func zoomIn(area: CGRect, memberFrames: [CGRect], labels: [String]) {
        guard let view else { return }
        let image = WindowCapture.below(window, bounds: area)
        func local(_ rect: CGRect) -> CGRect {
            rect.offsetBy(dx: -origin.x, dy: -origin.y)
        }
        let layout = HintZoom.layout(
            area: local(area),
            members: memberFrames.map(local),
            badgeSize: BadgeMetrics.size(forLabelLength: labels.first?.count ?? 1),
            bounds: view.bounds
        )
        view.typed = ""
        view.zoom = HintOverlayView.Zoom(
            panel: layout.panel,
            canvas: layout.canvas,
            image: image,
            content: layout.content,
            badges: layout.badges.indices.map { index in
                HintOverlayView.Badge(
                    rect: layout.badges[index],
                    label: labels[index],
                    target: layout.content[index],
                    caret: HintOverlayView.caretDirection(
                        from: layout.badges[index], toward: layout.content[index]
                    )
                )
            }
        )
    }

    /// Leaves the zoom and reveals the group badges again.
    func clearZoom() {
        view?.zoom = nil
        view?.typed = ""
    }

    /// Lays a fresh transparent, click-through overlay window over the screen
    /// containing the target window and returns its view, or nil if there's no
    /// screen.
    @discardableResult
    private func install(around windowFrame: CGRect) -> HintOverlayView? {
        hide()
        guard let primary = NSScreen.screens.first else { return nil }
        let frame = HintScreens.bounds(around: windowFrame)
        let cocoaFrame = HintGeometry.cocoaRect(
            fromAX: frame, primaryScreenHeight: primary.frame.height
        )

        let window = NSWindow(
            contentRect: cocoaFrame, styleMask: .borderless, backing: .buffered, defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        window.isReleasedWhenClosed = false

        let view = HintOverlayView(frame: CGRect(origin: .zero, size: cocoaFrame.size))
        view.windowRegion = windowFrame.offsetBy(dx: -frame.minX, dy: -frame.minY)
        window.contentView = view
        window.orderFrontRegardless()

        self.window = window
        self.view = view
        self.origin = frame.origin
        return view
    }

    func update(typed: String) {
        view?.typed = typed
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
        view = nil
    }

    /// Flashes a self-dismissing banner over the window — for error states
    /// where no mode session exists to own (and later hide) an overlay.
    static func flash(_ text: String, windowFrame: CGRect, duration: TimeInterval = 3) {
        let overlay = HintOverlay()
        overlay.showBanner(text, windowFrame: windowFrame)
        // The capture keeps the throwaway overlay alive until it hides itself.
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            overlay.hide()
        }
    }

    /// Runs the presentation half of a `LabelSession` effect. `.commit` and
    /// `.unwound` are the mode's own to handle; they draw nothing.
    func apply(_ effect: LabelSession.Effect) {
        switch effect {
        case .updateTyped(let typed):
            update(typed: typed)
        case .zoomIn(let area, let memberFrames, let labels):
            zoomIn(area: area, memberFrames: memberFrames, labels: labels)
        case .zoomOut:
            clearZoom()
        case .reject:
            NSSound.beep()
        case .commit, .unwound:
            break
        }
    }
}
