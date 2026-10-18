import AppKit
import SwiftUI
import Terminal

/// What "Import from Ghostty" will change, before it changes anything: each setting's current
/// value and the one from Ghostty, or why it stays.
struct TerminalImportSheet: View {
    let ghosttyImport: TerminalImport
    let current: TerminalSettings
    let apply: () -> Void
    let cancel: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text("Import from Ghostty")
                    .font(.dsTitle3)
                    .foregroundStyle(.dsTextPrimary)
                Text(source)
                    .font(.dsBody)
                    .foregroundStyle(.dsTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if ghosttyImport.files.isEmpty || ghosttyImport.isEmpty {
                EmptyStateView(
                    ghosttyImport.files.isEmpty ? "No Ghostty config found" : "Nothing to import",
                    systemImage: "square.and.arrow.down",
                    message: ghosttyImport.files.isEmpty
                        ? "Native looks in ~/.config/ghostty and ~/Library/Application Support/com.mitchellh.ghostty."
                        : "Your Ghostty config doesn't set a font, colors, cursor or scrollback."
                )
                .frame(height: 160)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    row("Font", from: current.fontFamily ?? "Geist Mono", to: font)
                    row("Size", from: "\(Int(current.fontSize)) pt", to: ghosttyImport.fontSize.map { "\(Int($0)) pt" })
                    colorsRow
                    row("Cursor", from: current.cursor.title, to: ghosttyImport.cursor?.title)
                    row("Scrollback", from: current.scrollback.title, to: ghosttyImport.scrollback?.title)
                }
            }
            HStack(spacing: DS.Space.md) {
                Spacer()
                Button("Cancel", action: cancel)
                    .buttonStyle(.ds(.secondary, size: .large))
                    .keyboardShortcut(.cancelAction)
                Button("Import", action: apply)
                    .buttonStyle(.ds(.primary, size: .large))
                    .keyboardShortcut(.defaultAction)
                    .disabled(ghosttyImport.isEmpty)
            }
        }
        .padding(DS.Space.xxl)
        .frame(width: 520)
        .background(.dsOverlay)
    }

    private var source: String {
        let names = ghosttyImport.files.map(\.abbreviatedPath)
        guard let first = names.first else { return "Copies your Ghostty settings into Native's, once." }
        let more = names.count > 1 ? " and \(names.count - 1) included file\(names.count > 2 ? "s" : "")" : ""
        return "From \(first)\(more). Native's settings change; your Ghostty config doesn't."
    }

    /// The imported family, or why it isn't one Native can use.
    private var font: String? {
        guard let family = ghosttyImport.fontFamily else { return nil }
        return NSFontManager.shared.availableFontFamilies.contains(family) ? family : "\(family) (not installed)"
    }

    @ViewBuilder private var colorsRow: some View {
        let currentName =
            switch current.colors {
            case .app: "Native's"
            case .imported(let imported): imported.themeName ?? "Imported"
            }
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.md) {
            label("Colors")
            if let colors = ghosttyImport.colors {
                HStack(spacing: DS.Space.sm) {
                    swatches(colors.colors(for: TerminalAppearance(colorScheme)))
                    Text(colors.themeName ?? "Your config's colors")
                        .font(.dsBodyMedium)
                        .foregroundStyle(.dsTextPrimary)
                }
            } else {
                unchanged(currentName)
            }
        }
        .padding(.vertical, DS.Space.sm)
    }

    private func row(_ title: String, from current: String, to imported: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.md) {
            label(title)
            if let imported, imported != current {
                Text(current)
                    .font(.dsBody)
                    .foregroundStyle(.dsTextTertiary)
                    .strikethrough()
                Image(systemName: "arrow.right")
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextTertiary)
                Text(imported)
                    .font(.dsBodyMedium)
                    .foregroundStyle(.dsTextPrimary)
            } else {
                unchanged(current)
            }
        }
        .padding(.vertical, DS.Space.sm)
    }

    private func label(_ title: String) -> some View {
        Text(title)
            .font(.dsBody)
            .foregroundStyle(.dsTextSecondary)
            .frame(width: 88, alignment: .leading)
    }

    private func unchanged(_ value: String) -> some View {
        Text("\(value) · not set in Ghostty, stays")
            .font(.dsBody)
            .foregroundStyle(.dsTextTertiary)
    }

    /// The background with the eight normal ANSI colors on it.
    private func swatches(_ colors: TerminalColors) -> some View {
        HStack(spacing: DS.Space.xxs) {
            ForEach(Array(colors.palette.prefix(8).enumerated()), id: \.offset) { _, color in
                RoundedRectangle(cornerRadius: DS.Radius.small)
                    .fill(Color(color))
                    .frame(width: 10, height: 10)
            }
        }
        .padding(DS.Space.xs)
        .background(Color(colors.chrome.background), in: .rect(cornerRadius: DS.Radius.control))
        .accessibilityHidden(true)
    }
}

extension TerminalCursor {
    var title: String {
        "\(style.title)\(blinks ? ", blinking" : "")"
    }
}
