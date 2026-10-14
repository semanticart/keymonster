import AppKit
import SwiftUI

/// Draws a ShortcutSheet as a multi-page, vector US Letter PDF. Colors are
/// fixed (printed paper doesn't follow dark mode), and every row has the height
/// ShortcutSheetLayout assumed when it paged the content.
enum ShortcutSheetPDF {
    static let defaultFileName = "Key Monster Shortcuts.pdf"

    @MainActor
    static func data(for sheet: ShortcutSheet, date: Date = Date()) -> Data? {
        let pages = ShortcutSheetLayout.paginate(sheet)
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: ShortcutSheetLayout.pageSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &box, [
                  kCGPDFContextTitle: "Key Monster Shortcuts",
                  kCGPDFContextCreator: "Key Monster"
              ] as CFDictionary) else { return nil }

        for (index, page) in pages.enumerated() {
            let view = SheetPageView(
                sheet: sheet, page: page, pageNumber: index + 1, pageCount: pages.count, date: date
            )
            let renderer = ImageRenderer(content: view)
            renderer.proposedSize = ProposedViewSize(ShortcutSheetLayout.pageSize)
            renderer.render { _, draw in
                context.beginPDFPage(nil)
                draw(context)
                context.endPDFPage()
            }
        }
        context.closePDF()
        return data as Data
    }

    /// Ask where to save, write the PDF, and open it. Cancelling does nothing.
    @MainActor
    static func saveInteractively(settings: AppSettings) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = defaultFileName
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.canCreateDirectories = true
        panel.message = "Save a printable sheet of your Key Monster shortcuts"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard let pdf = data(for: ShortcutSheet(settings: settings)) else {
            presentFailure("The PDF could not be created.")
            return
        }
        do {
            try pdf.write(to: url, options: .atomic)
            NSWorkspace.shared.open(url)
        } catch {
            presentFailure(error.localizedDescription)
        }
    }

    @MainActor
    private static func presentFailure(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Couldn't save the shortcut sheet"
        alert.informativeText = message
        alert.runModal()
    }
}

// MARK: - Palette

private enum Ink {
    static let paper = Color(red: 0.99, green: 0.985, blue: 0.975)
    static let text = Color(red: 0.11, green: 0.12, blue: 0.15)
    static let secondary = Color(red: 0.43, green: 0.45, blue: 0.50)
    static let faint = Color(red: 0.62, green: 0.64, blue: 0.68)
    static let rule = Color(red: 0.89, green: 0.89, blue: 0.90)
    static let accent = Color(red: 0.10, green: 0.41, blue: 0.71) // the monster's blue
    static let capFill = Color.white
    static let capEdge = Color(red: 0.78, green: 0.80, blue: 0.83)
    static let warning = Color(red: 0.85, green: 0.45, blue: 0.05)
}

// MARK: - Page

private struct SheetPageView: View {
    let sheet: ShortcutSheet
    let page: ShortcutSheetLayout.Page
    let pageNumber: Int
    let pageCount: Int
    let date: Date

    private typealias Layout = ShortcutSheetLayout

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if page.isFirst {
                titleBlock
                    .frame(height: Layout.titleBlockHeight, alignment: .topLeading)
            }
            ForEach(Array(page.items.enumerated()), id: \.offset) { index, item in
                itemView(item, atTop: index == 0)
            }
            Spacer(minLength: 0)
            footer
                .frame(height: Layout.footerHeight, alignment: .bottom)
        }
        .padding(.horizontal, Layout.margin)
        .padding(.vertical, Layout.margin)
        .frame(width: Layout.pageSize.width, height: Layout.pageSize.height, alignment: .topLeading)
        .background(Ink.paper)
        .environment(\.colorScheme, .light)
    }

    private var summary: String {
        var parts = ["\(sheet.assignedCount) of \(sheet.allEntries.count) assigned"]
        if sheet.unassignedCount > 0 { parts.append("\(sheet.unassignedCount) unassigned") }
        if sheet.conflictCount > 0 { parts.append("\(sheet.conflictCount) in conflict") }
        return parts.joined(separator: " · ")
    }

    /// The Canvas-drawn icon loses its gradients in vector PDF output (the blue
    /// fur vanishes), so it is rasterized once, large enough to stay crisp.
    @MainActor
    private var icon: some View {
        let renderer = ImageRenderer(content: AppIconView().frame(width: 64, height: 64))
        renderer.scale = 8
        return Group {
            if let image = renderer.nsImage {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                AppIconView()
            }
        }
    }

    private var titleBlock: some View {
        HStack(alignment: .top, spacing: 16) {
            icon
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text("Keyboard Shortcuts")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Ink.text)
                Text("Key Monster")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Ink.accent)
                Text(summary)
                    .font(.system(size: 11))
                    .foregroundStyle(Ink.secondary)
            }
            Spacer()
        }
    }

    private var footer: some View {
        HStack {
            Text("Key Monster · " + date.formatted(date: .long, time: .omitted))
            Spacer()
            Text("Page \(pageNumber) of \(pageCount)")
        }
        .font(.system(size: 9))
        .foregroundStyle(Ink.faint)
    }

    @ViewBuilder
    private func itemView(_ item: Layout.Item, atTop: Bool) -> some View {
        switch item {
        case let .header(section, continued):
            SectionHeader(section: section, continued: continued)
                .padding(.top, atTop ? 0 : Layout.sectionGap)
                .frame(height: Layout.height(of: item, atTop: atTop), alignment: .bottom)
        case let .row(entry):
            EntryRow(entry: entry)
                .frame(height: Layout.rowHeight)
        case let .emptyNote(note):
            Text(note)
                .font(.system(size: 11))
                .italic()
                .foregroundStyle(Ink.faint)
                .frame(maxWidth: .infinity, minHeight: Layout.rowHeight, alignment: .leading)
                .frame(height: Layout.rowHeight)
        }
    }
}

// MARK: - Pieces

private struct SectionHeader: View {
    let section: ShortcutSheet.Section
    let continued: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: section.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Ink.accent)
                    .frame(width: 16)
                Text(section.title.uppercased() + (continued ? " (CONTINUED)" : ""))
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(Ink.accent)
                Spacer()
            }
            Rectangle().fill(Ink.accent.opacity(0.5)).frame(height: 1.5)
        }
    }
}

private struct EntryRow: View {
    let entry: ShortcutSheet.Entry

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(entry.isAssigned ? Ink.text : Ink.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(entry.detail)
                        .font(.system(size: 10))
                        .foregroundStyle(Ink.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                if entry.isConflicting {
                    Text("CONFLICT")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(Ink.warning)
                }
                if let caps = entry.keyCaps {
                    HStack(spacing: 4) {
                        ForEach(Array(caps.enumerated()), id: \.offset) { _, cap in
                            KeyCap(label: cap)
                        }
                    }
                } else {
                    UnassignedBadge()
                }
            }
            .frame(maxHeight: .infinity)
            Rectangle().fill(Ink.rule).frame(height: 0.5)
        }
    }
}

private struct KeyCap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: label.count > 1 ? 11 : 14, weight: .medium, design: .rounded))
            .foregroundStyle(Ink.text)
            .frame(minWidth: 26, minHeight: 26)
            .padding(.horizontal, label.count > 1 ? 6 : 0)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Ink.capFill)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Ink.capEdge, lineWidth: 0.75))
                    // The thicker lower edge gives the cap its raised look.
                    .shadow(color: Ink.capEdge, radius: 0, x: 0, y: 1.5)
            )
    }
}

private struct UnassignedBadge: View {
    var body: some View {
        Text("Unassigned")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Ink.faint)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Ink.faint, style: StrokeStyle(lineWidth: 0.75, dash: [3, 2.5]))
            )
    }
}
