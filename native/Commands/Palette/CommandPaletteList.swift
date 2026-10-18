import NativeCommands
import SwiftUI

/// The palette's results: section headings over rows, scrolled to keep the selection in view.
struct CommandPaletteList: View {
    let results: CommandPaletteResults
    let query: String
    @Binding var selection: CommandPaletteItem.ID?
    let maxHeight: CGFloat
    let onRun: (CommandPaletteItem) -> Void

    @State private var contentHeight: CGFloat = 0

    /// The row Return runs: the one moved to, or the first.
    private var selectedID: CommandPaletteItem.ID? {
        results.rows.contains { $0.id == selection } ? selection : results.rows.first?.id
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if results.rows.isEmpty {
                        empty
                    }
                    ForEach(results.sections) { section in
                        Text(section.title)
                            .font(.dsCaptionMedium)
                            .foregroundStyle(.dsTextTertiary)
                            .padding(.horizontal, DS.Space.md)
                            .padding(.top, DS.Space.md)
                            .padding(.bottom, DS.Space.xs)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(section.rows) { row in
                            CommandPaletteRow(row: row, isSelected: row.id == selectedID, showsHighlights: !query.isEmpty) {
                                onRun(row.item)
                            }
                            .onHover { if $0 { selection = row.id } }
                            .id(row.id)
                        }
                    }
                }
                .padding(DS.Space.xs)
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.height
                } action: {
                    contentHeight = $0
                }
            }
            .frame(height: min(contentHeight, maxHeight))
            .onChange(of: selection) {
                if let selection {
                    proxy.scrollTo(selection)
                }
            }
        }
    }

    private var empty: some View {
        Text("Nothing matches \u{201C}\(query.trimmingCharacters(in: .whitespaces))\u{201D}")
            .font(.dsBody)
            .foregroundStyle(.dsTextSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Space.xxl)
    }
}

/// One result: its icon, title (matched letters at full strength), a dim subtitle, a checkmark for
/// on/off commands, and its shortcut.
private struct CommandPaletteRow: View {
    let row: CommandPaletteResults.Row
    let isSelected: Bool
    let showsHighlights: Bool
    let action: () -> Void

    var body: some View {
        let item = row.item
        Button(action: action) {
            HStack(spacing: DS.Space.md) {
                Image(systemName: item.systemImage)
                    .font(.dsBody)
                    .foregroundStyle(isSelected ? .dsTextPrimary : .dsTextSecondary)
                    .frame(width: DS.Size.rowLeading)
                    .accessibilityHidden(true)
                HStack(spacing: DS.Space.sm) {
                    Text(title)
                        .lineLimit(1)
                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .foregroundStyle(.dsTextTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .font(.dsBody)
                .frame(maxWidth: .infinity, alignment: .leading)
                if item.isOn == true {
                    Image(systemName: "checkmark")
                        .font(.dsCaptionMedium)
                        .foregroundStyle(.dsTextSecondary)
                        .accessibilityLabel("On")
                }
                if let shortcut = item.shortcut {
                    Kbd(shortcut.displayString)
                }
            }
            .padding(.horizontal, DS.Space.md)
            .frame(minHeight: max(DS.Size.controlMD, DS.minimumHitTarget))
            .background(isSelected ? Color.dsSelected : .clear, in: .rect(cornerRadius: DS.Radius.row))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// The title with the matched letters at full strength and the rest dimmed, as Conductor's
    /// search shows it.
    private var title: AttributedString {
        var text = AttributedString(row.item.title)
        guard showsHighlights, !row.highlights.isEmpty else {
            text.foregroundColor = .dsTextPrimary
            return text
        }
        text.foregroundColor = .dsTextSecondary
        let characters = Array(text.characters.indices)
        for range in row.highlights where range.lowerBound < characters.count {
            let end = range.upperBound < characters.count ? characters[range.upperBound] : text.endIndex
            text[characters[range.lowerBound]..<end].foregroundColor = .dsTextPrimary
        }
        return text
    }
}
