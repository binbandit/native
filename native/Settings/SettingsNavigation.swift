import SwiftUI

/// The left column of Settings: the search field, then pages under
/// muted group labels. The list is one keyboard stop, like a macOS sidebar: ↑ and ↓ change the page.
struct SettingsNavigation<Search: View>: View {
    let panes: [SettingsPane]
    @Binding var selection: SettingsPane.ID
    var focus: FocusState<SettingsScreen.Focus?>.Binding
    @ViewBuilder var search: Search

    /// Nav items get a ring only for keyboard focus, not after a click or when Settings opens, where
    /// it would just be noise.
    @Environment(\.settingsPlainly) private var plainly
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
                .padding(.trailing, plainly ? DS.Space.xxs : 0)
                .padding(.top, plainly ? DS.Space.xxs : DS.Space.xs)
                .padding(.bottom, plainly ? DS.Settings.searchBottomInset : DS.Space.lg)
                .zIndex(1)
            ScrollView {
                list
                    .padding(.bottom, DS.Space.lg)
            }
            .scrollEdgeEffectStyle(.soft, for: .vertical)
        }
        .padding(.leading, plainly ? DS.Settings.navInset : DS.Space.sm)
        .padding(.trailing, plainly ? DS.Settings.navInset : DS.Space.md)
        .frame(maxHeight: .infinity, alignment: .top)
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
        VStack(alignment: .leading, spacing: plainly ? DS.Settings.navGroupGap : SettingsMetrics.navGroupSpacing) {
            ForEach(groups, id: \.group) { entry in
                VStack(alignment: .leading, spacing: 0) {
                    if plainly {
                        if entry.group != .personal {
                            Text(entry.group.title)
                                .font(DS.Settings.navGroup)
                                .foregroundStyle(.dsTextTertiary)
                                .padding(.horizontal, DS.Settings.navInset)
                                .padding(.bottom, DS.Space.sm)
                                .accessibilityAddTraits(.isHeader)
                        }
                    } else {
                        Text(entry.group.title)
                            .settingsText(.caption)
                            .foregroundStyle(.dsTextSecondary)
                            .padding(.horizontal, DS.Space.md)
                            .padding(.vertical, DS.Space.sm)
                            .accessibilityAddTraits(.isHeader)
                    }
                    VStack(spacing: plainly ? DS.Settings.navRowGap : SettingsMetrics.navItemSpacing) {
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

/// A nav row (32pt, 6pt radius, 16pt icon 12pt before a 14pt label; muted until
/// selected, when it takes the sidebar's selection fill and turns medium; hovering washes it and
/// brightens the icon). Both fills are translucent, as everything on the sidebar is.
private struct NavItem: View {
    let pane: SettingsPane
    let isSelected: Bool
    let showsFocusRing: Bool
    let action: () -> Void

    @Environment(\.settingsPlainly) private var plainly
    @State private var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
        Button(action: action) {
            HStack(spacing: plainly ? DS.Settings.navGap : DS.Space.lg) {
                Group {
                    if let navIcon = pane.navIcon {
                        navIcon()
                    } else {
                        Image(systemName: pane.systemImage)
                            .font(.system(size: SettingsMetrics.navGlyph, weight: .thin))
                            .foregroundStyle(isSelected || isHovered ? Color.dsTextPrimary : Color.dsTextSecondary)
                    }
                }
                .frame(width: SettingsMetrics.navIcon, height: SettingsMetrics.navIcon)
                Text(pane.title)
                    .settingsText(isSelected ? .bodyMedium : .body)
                    .foregroundStyle(isSelected ? Color.dsTextPrimary : Color.dsTextSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, plainly ? DS.Settings.navInset : DS.Space.md)
            .padding(.vertical, plainly ? DS.Space.xs : DS.Space.sm)
            .frame(minHeight: plainly ? max(DS.Settings.navRowHeight, DS.Size.minimumHitTarget) : nil)
            .background(isSelected ? Color.dsSelected : isHovered ? .dsHover : .clear, in: shape)
            .overlay {
                if showsFocusRing {
                    // A 2pt ring, in the accent color the system draws focus rings in. It
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

#if DEBUG
#Preview("Settings navigation") {
    DSPreviewPair {
        SettingsNavigationPreview()
            .frame(width: SettingsMetrics.navWidth, height: 640)
    }
}

/// Holds the selection and focus the navigation takes as bindings.
private struct SettingsNavigationPreview: View {
    @State private var selection = SettingsPane.ID.general
    @FocusState private var focus: SettingsScreen.Focus?
    private let registry = SettingsPreviewFixtures.registry()

    var body: some View {
        SettingsNavigation(
            panes: SettingsPane.builtIn(registry: registry).sorted { ($0.group, $0.order) < ($1.group, $1.order) },
            selection: $selection, focus: $focus
        ) {
            EmptyView()
        }
    }
}
#endif
