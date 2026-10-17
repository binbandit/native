import SwiftUI

/// Conductor's settings search: a 28pt field with the ⌘F hint, and results in a popup under it.
/// ↑ and ↓ move through results, Return opens one, Escape clears the search.
struct SettingsSearchField: View {
    @Binding var query: String
    let results: [SettingsSearchIndex.Result]
    @Binding var highlighted: Int
    var focus: FocusState<SettingsScreen.Focus?>.Binding
    let onPick: (SettingsSearchIndex.Item) -> Void

    private var isOpen: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }
    private var isFocused: Bool { focus.wrappedValue == .search }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
        TextField("Search settings", text: $query, prompt: Text("Search settings").foregroundStyle(.dsTextTertiary))
            .textFieldStyle(.plain)
            .settingsText(.body)
            .foregroundStyle(.dsTextPrimary)
            .focused(focus, equals: .search)
            .padding(.leading, DS.Space.xxxl)
            .padding(.trailing, DS.Space.xxl + DS.Space.xl)
            .frame(height: DS.Size.controlSM)
            .overlay(alignment: .leading) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: SettingsMetrics.searchGlyph, weight: .regular))
                    .foregroundStyle(.dsTextSecondary)
                    .padding(.leading, DS.Space.md + DS.Space.xxs)
                    .accessibilityHidden(true)
            }
            .overlay(alignment: .trailing) {
                trailingAccessory
                    .padding(.trailing, DS.Space.md)
            }
            .background(.dsBackground, in: shape)
            .overlay { shape.strokeBorder(isFocused ? Color.dsAccent : Color.dsBorder, lineWidth: 1) }
            .onKeyPress(.downArrow) { moveHighlight(by: 1) }
            .onKeyPress(.upArrow) { moveHighlight(by: -1) }
            .onKeyPress(.return) {
                guard isOpen else { return .ignored }
                if results.indices.contains(highlighted) {
                    onPick(results[highlighted].item)
                }
                return .handled
            }
            .onKeyPress(.escape) {
                guard !query.isEmpty else { return .ignored }
                query = ""
                return .handled
            }
            .onChange(of: query) { highlighted = 0 }
            .overlay(alignment: .top) {
                if isOpen {
                    SettingsSearchResults(query: query, results: results, highlighted: $highlighted, onPick: onPick)
                        .offset(y: DS.Size.controlSM + SettingsMetrics.resultsOffset)
                }
            }
    }

    @ViewBuilder
    private var trailingAccessory: some View {
        if query.isEmpty {
            SearchShortcutHint(parts: ["⌘", "F"])
        } else {
            Button {
                query = ""
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: SettingsMetrics.searchGlyph - 2, weight: .medium))
                    .foregroundStyle(.dsTextSecondary)
                    .padding(DS.Space.xxs)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear Settings Search")
        }
    }

    private func moveHighlight(by step: Int) -> KeyPress.Result {
        guard isOpen, !results.isEmpty else { return .ignored }
        highlighted = min(max(highlighted + step, 0), results.count - 1)
        return .handled
    }
}

/// The popup under the field (Conductor: anchor-wide, 8pt radius, sidebar fill, at most 480pt
/// tall, results with the matched letters at full strength and the rest dimmed).
private struct SettingsSearchResults: View {
    let query: String
    let results: [SettingsSearchIndex.Result]
    @Binding var highlighted: Int
    let onPick: (SettingsSearchIndex.Item) -> Void

    @State private var contentHeight: CGFloat = 0

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: DS.Space.xxs) {
                    if results.isEmpty {
                        Text("No settings match \u{201C}\(query)\u{201D}")
                            .settingsText(.caption)
                            .foregroundStyle(.dsTextSecondary)
                            .padding(.horizontal, DS.Space.md)
                            .padding(.vertical, DS.Space.sm)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                        ResultRow(result: result, isHighlighted: index == highlighted) {
                            onPick(result.item)
                        }
                        .onHover { if $0 { highlighted = index } }
                        .id(index)
                    }
                }
                .padding(DS.Space.xs)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .frame(height: min(contentHeight, SettingsMetrics.resultsMaxHeight))
            .onChange(of: highlighted) { proxy.scrollTo(highlighted) }
        }
        .background(.dsSurfaceSunken, in: shape)
        .clipShape(shape)
        .overlay { shape.strokeBorder(.dsSeparator, lineWidth: 1) }
        .dsShadow(.modal)
    }
}

private struct ResultRow: View {
    let result: SettingsSearchIndex.Result
    let isHighlighted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: DS.Space.lg) {
                Image(systemName: result.item.systemImage)
                    .font(.system(size: SettingsMetrics.navGlyph, weight: .thin))
                    .foregroundStyle(.dsTextSecondary)
                    .frame(width: SettingsMetrics.navIcon, height: SettingsMetrics.navIcon)
                    .padding(.top, DS.Space.xxs)
                VStack(alignment: .leading, spacing: 0) {
                    Text(highlightedTitle)
                        .settingsText(.body)
                        .lineLimit(1)
                    if result.item.rowID != nil {
                        Text(result.item.paneTitle)
                            .settingsText(.caption)
                            .foregroundStyle(.dsTextSecondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, DS.Space.md)
            .padding(.vertical, DS.Space.sm)
            .background(isHighlighted ? Color.dsHover : .clear, in: RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(result.item.rowID == nil ? result.item.title : "\(result.item.title), \(result.item.paneTitle)")
    }

    /// Matched letters at full strength, the rest at half, as Conductor highlights matches. A
    /// result found through its description or keywords is all dimmed.
    private var highlightedTitle: AttributedString {
        var title = AttributedString()
        for (offset, character) in result.item.title.enumerated() {
            var run = AttributedString(String(character))
            run.foregroundColor = result.titleMatches.contains(offset) ? .dsTextPrimary : .dsTextPrimary.opacity(0.5)
            title += run
        }
        return title
    }
}
