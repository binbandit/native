import SwiftUI

/// The left column of Settings after Conductor's settings nav: the search field, then pages under
/// muted group labels. The list is one keyboard stop, like a macOS sidebar: ↑ and ↓ change the page.
struct SettingsNavigation<Search: View>: View {
    let panes: [SettingsPane]
    @Binding var selection: SettingsPane.ID
    var focus: FocusState<SettingsScreen.Focus?>.Binding
    @ViewBuilder var search: Search

    /// Conductor rings nav items only for keyboard focus (`focus-visible`), not after a click or
    /// when Settings opens.
    @State private var showsFocusRing = false
    @State private var isFocusingQuietly = false

    private var groups: [(group: SettingsPane.Group, panes: [SettingsPane])] {
        Dictionary(grouping: panes, by: \.group)
            .sorted { $0.key < $1.key }
            .map { (group: $0.key, panes: $0.value) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            search
                .padding(.leading, DS.Space.xxs)
                .padding(.top, DS.Space.xs)
                .padding(.bottom, DS.Space.lg)
                .zIndex(1)
            ScrollView {
                list
                    .padding(.bottom, DS.Space.lg)
            }
            .scrollEdgeEffectStyle(.soft, for: .vertical)
        }
        .padding(.leading, DS.Space.sm)
        .padding(.trailing, DS.Space.md)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.dsBackground)
        .overlay(alignment: .trailing) {
            // Conductor's `border-r`, full height, under the toolbar too.
            SeparatorLine(axis: .vertical)
                .ignoresSafeArea()
        }
        .onChange(of: focus.wrappedValue) { _, newValue in
            showsFocusRing = newValue == .navigation && !isFocusingQuietly
            isFocusingQuietly = false
        }
        .onAppear {
            // Opening Settings puts the keyboard in the nav, so ↑ and ↓ work right away.
            isFocusingQuietly = true
            focus.wrappedValue = .navigation
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.navGroupSpacing) {
            ForEach(groups, id: \.group) { entry in
                VStack(alignment: .leading, spacing: 0) {
                    Text(entry.group.title)
                        .settingsText(.caption)
                        .foregroundStyle(.dsTextSecondary)
                        .padding(.horizontal, DS.Space.md)
                        .padding(.vertical, DS.Space.sm)
                        .accessibilityAddTraits(.isHeader)
                    VStack(spacing: SettingsMetrics.navItemSpacing) {
                        ForEach(entry.panes) { pane in
                            NavItem(
                                pane: pane,
                                isSelected: pane.id == selection,
                                showsFocusRing: showsFocusRing && focus.wrappedValue == .navigation
                                    && pane.id == selection
                            ) {
                                select(pane.id)
                            }
                        }
                    }
                }
            }
        }
        .focusable()
        .focused(focus, equals: .navigation)
        .focusEffectDisabled()
        .onKeyPress(.downArrow) { move(by: 1) }
        .onKeyPress(.upArrow) { move(by: -1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings pages")
    }

    private func select(_ id: SettingsPane.ID) {
        selection = id
        if focus.wrappedValue != .navigation {
            isFocusingQuietly = true
            focus.wrappedValue = .navigation
        }
        showsFocusRing = false
    }

    private func move(by step: Int) -> KeyPress.Result {
        let ordered = groups.flatMap(\.panes)
        guard let index = ordered.firstIndex(where: { $0.id == selection }) else { return .ignored }
        let next = min(max(index + step, 0), ordered.count - 1)
        selection = ordered[next].id
        showsFocusRing = true
        return .handled
    }
}

/// A nav row (Conductor: 32pt, 6pt radius, 16pt icon 12pt before a 14pt label; muted until
/// selected, when it fills and turns medium; hovering fills it and brightens the icon).
private struct NavItem: View {
    let pane: SettingsPane
    let isSelected: Bool
    let showsFocusRing: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
        Button(action: action) {
            HStack(spacing: DS.Space.lg) {
                Image(systemName: pane.systemImage)
                    .font(.system(size: SettingsMetrics.navGlyph, weight: .thin))
                    .foregroundStyle(isSelected || isHovered ? Color.dsTextPrimary : Color.dsTextSecondary)
                    .frame(width: SettingsMetrics.navIcon, height: SettingsMetrics.navIcon)
                Text(pane.title)
                    .settingsText(isSelected ? .bodyMedium : .body)
                    .foregroundStyle(isSelected ? Color.dsTextPrimary : Color.dsTextSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Space.md)
            .padding(.vertical, DS.Space.sm)
            .background(isSelected || isHovered ? Color.dsHover : .clear, in: shape)
            .overlay {
                if showsFocusRing {
                    // Conductor's 2pt ring, in the accent color the system draws focus rings in. It
                    // sits on the row's edge rather than outside it, where the scroll view would clip it.
                    shape.strokeBorder(.tint, lineWidth: 2)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .trackHover($isHovered)
        .help(pane.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
