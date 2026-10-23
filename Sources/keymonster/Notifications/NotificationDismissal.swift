import Foundation

/// The slice of an accessibility tree that notification dismissal reads, so the
/// walk can be tested against hand-built trees without a live Notification
/// Center (which a CI machine can't read anyway).
protocol NotificationTree {
    associatedtype Element

    func children(of element: Element) -> [Element]
    func subrole(of element: Element) -> String?
    /// Raw action names. Notification Center's own actions arrive as
    /// `Name:Close|Target:0x0|Selector:(null)`, not as bare `AXPress`-style names.
    func actionNames(of element: Element) -> [String]
    @discardableResult
    func perform(_ action: String, on element: Element) -> Bool
}

/// The display names Notification Center gives its dismiss verbs. English is
/// always included; `localized(from:)` adds every translation Notification
/// Center ships, so the match works whatever language it is running in.
struct DismissNames {
    private let lowercased: Set<String>

    init(_ names: some Sequence<String>) {
        lowercased = Set(names.map(Self.normalize))
    }

    static let english = DismissNames(["Close", "Clear All", "Clear"])

    func contains(_ name: String) -> Bool { lowercased.contains(Self.normalize(name)) }

    private static func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Where Notification Center keeps its strings: one table per language.
    static let loctableURL = URL(fileURLWithPath:
        "/System/Library/CoreServices/NotificationCenter.app/Contents/Resources/Localizable.loctable")

    /// The verbs from a `Localizable.loctable` (`[language: [key: string]]`),
    /// in every language, plus English. The keys are the English strings.
    static func localized(fromTables tables: [String: Any]) -> DismissNames {
        var names = ["Close", "Clear All", "Clear"]
        for case let table as [String: Any] in tables.values {
            for key in ["Close", "Clear All", "Clear"] {
                if let translated = table[key] as? String { names.append(translated) }
            }
        }
        return DismissNames(names)
    }

    /// Reads the loctable at `url`; English alone when it's missing or unreadable
    /// (the file's layout is Apple's, and may differ on other macOS versions).
    static func localized(from url: URL = loctableURL) -> DismissNames {
        guard let data = try? Data(contentsOf: url),
              let tables = try? PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any] else { return .english }
        return localized(fromTables: tables)
    }
}

/// Finds notification banners and stacks in Notification Center's tree and
/// presses their dismiss action. Pure over `NotificationTree`.
///
/// Notification Center models each banner as an `AXGroup` with subrole
/// `AXNotificationCenterBanner` carrying custom actions such as `Show` and
/// `Close`. A stack of grouped notifications offers `Clear All` instead, which
/// removes the whole stack, so it wins over `Close` when both are present.
enum NotificationDismissal {
    /// Every notification element carries this subrole prefix
    /// (`AXNotificationCenterBanner`, `AXNotificationCenterAlert`, …); matching
    /// the prefix keeps stacks and alert-style notifications working even though
    /// only the banner is confirmed against a live system.
    static let subrolePrefix = "AXNotificationCenter"

    /// The display name inside a custom action string (`Name:Close\nTarget:…`),
    /// or nil when it isn't one of Notification Center's custom actions.
    static func displayName(of action: String) -> String? {
        guard action.hasPrefix("Name:") else { return nil }
        let rest = action.dropFirst("Name:".count)
        return String(rest.prefix { $0 != "\n" && $0 != "|" })
    }

    /// The action to press to dismiss a notification offering `actions`, or nil.
    ///
    /// Notification Center always puts its own dismiss verb (`Close` on a
    /// banner, `Clear All` on a stack) *last*, after `Show` and any actions the
    /// posting app adds, so position finds it in every language. The name must
    /// still be a known dismiss verb: that guards against a future layout change
    /// pressing something else, and it is why an app's own action that happens to
    /// be called "Close" earlier in the list is never mistaken for the real one.
    static func dismissAction(in actions: [String], names: DismissNames) -> String? {
        guard let last = actions.last(where: { $0.hasPrefix("Name:") }),
              let name = displayName(of: last), names.contains(name) else { return nil }
        return last
    }

    /// A notification element and the dismiss action to press on it.
    struct Target<Element> {
        let element: Element
        let action: String
    }

    /// Every dismissable notification under `roots`, in document order. A
    /// notification that is dismissable is never descended into: a stack's
    /// `Clear All` already covers the banners inside it.
    static func targets<Tree: NotificationTree>(
        in tree: Tree, roots: [Tree.Element], names: DismissNames
    ) -> [Target<Tree.Element>] {
        var found: [Target<Tree.Element>] = []
        var pending = roots.reversed().map { $0 }
        while let element = pending.popLast() {
            if tree.subrole(of: element)?.hasPrefix(subrolePrefix) == true,
               let action = dismissAction(in: tree.actionNames(of: element), names: names) {
                found.append(Target(element: element, action: action))
                continue
            }
            pending.append(contentsOf: tree.children(of: element).reversed())
        }
        return found
    }

    /// Dismisses every notification found under `roots` and returns how many
    /// actions succeeded. Targets are all collected before any is pressed, since
    /// dismissing one animates the tree and would invalidate a live walk.
    @discardableResult
    static func dismissAll<Tree: NotificationTree>(
        in tree: Tree, roots: [Tree.Element], names: DismissNames
    ) -> Int {
        targets(in: tree, roots: roots, names: names)
            .filter { tree.perform($0.action, on: $0.element) }
            .count
    }
}
