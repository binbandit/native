import SwiftUI

/// Settings as a full-window screen inside the main window, with a nav
/// column (Back, search, grouped pages) on the left and the selected page on the right.
///
/// The screen is open while `pane` is non-nil; Back and Escape set it to nil. Setting it to a pane
/// opens or deep-links to that page. Other features add pages through `additionalPanes`.
struct SettingsScreen: View {
    enum Focus: Hashable {
        case search
        case navigation
    }

    @Binding var pane: SettingsPane.ID?
    var additionalPanes: [SettingsPane] = []

    @Environment(PluginRegistry.self) private var registry
    @Environment(\.experimentStore) private var experiments
    private var plainly: Bool { SettingsPageMap.isEnabled(in: experiments ?? .shared) }
    @State private var query = ""
    @State private var highlightedResult = 0
    @State private var reveal: SettingsReveal?
    @State private var flash: SettingsReveal?
    /// Whether the page has scrolled under the toolbar, which then closes it off with a hairline.
    @State private var isScrolled = false
    @FocusState private var focus: Focus?
    /// At compact widths (iPad split view and slide over) the split view becomes a stack: the nav
    /// first, and picking a page pushes it.
    @State private var compactColumn = NavigationSplitViewColumn.sidebar

    private var panes: [SettingsPane] {
        SettingsPageMap.panes(
            SettingsPane.builtIn(registry: registry) + additionalPanes,
            registry: registry, plainly: plainly)
    }

    private var selectedPane: SettingsPane? {
        let destination = plainly ? pane.map(SettingsPageMap.destination) : pane
        return panes.first { $0.id == destination }
            ?? (plainly && destination == .toolsSkills ? panes.first { $0.id == .extensions } : nil)
            ?? panes.first
    }

    private var selection: Binding<SettingsPane.ID> {
        Binding(
            get: { selectedPane?.id ?? .general },
            set: {
                pane = $0
                compactColumn = .detail
            }
        )
    }

    var body: some View {
        // A split view, like the main window's, keeps the toolbar and window controls where they
        // are and puts Back at the nav's trailing edge.
        NavigationSplitView(columnVisibility: .constant(.all), preferredCompactColumn: $compactColumn) {
            SettingsNavigation(panes: panes, selection: selection, focus: $focus) {
                SettingsSearchField(
                    query: $query,
                    results: SettingsSearchIndex(panes: panes).results(for: query, limit: SettingsMetrics.resultsLimit),
                    highlighted: $highlightedResult,
                    focus: $focus,
                    onPick: open
                )
            }
            .dsSidebarColumnTransparency()
            // Applied after the width, this would make SwiftUI ignore the width.
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(SettingsMetrics.navWidth)
            .toolbar {
                ToolbarSpacer(.flexible)
                ToolbarItem {
                    SettingsBackButton(action: close)
                }
                .sharedBackgroundVisibility(.hidden)
            }
        } detail: {
            content
        }
        .toolbar(removing: .sidebarToggle)
        .toolbar(removing: .title)
        #if os(macOS)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        #endif
        .navigationTitle("Settings")
        .environment(\.settingsPlainly, plainly)
        .background {
            // Key equivalents, so they work wherever focus is (or isn't).
            Button("Search Settings") { focus = .search }
                .keyboardShortcut("f")
                .hidden()
            // While there's a query, Escape goes to the search field, which clears it.
            Button("Close Settings", action: close)
                .keyboardShortcut(.cancelAction)
                .disabled(!query.isEmpty)
                .hidden()
        }
        .onChange(of: focus) { _, newValue in
            // Clicking away from the search closes its results.
            if newValue != .search {
                query = ""
            }
        }
    }

    private var content: some View {
        ScrollViewReader { proxy in
            ScrollView {
                selectedPane?.makeContent()
                    .padding(.horizontal, SettingsMetrics.pageInset)
                    .padding(.top, plainly ? DS.Settings.pageTopInset : SettingsMetrics.pageTopInset)
                    .padding(.bottom, SettingsMetrics.pageBottomInset)
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 0
            } action: { _, isScrolled in
                self.isScrolled = isScrolled
            }
            .task(id: reveal) {
                guard let reveal else { return }
                // A destination can change scope or open a disclosure before its target lays out.
                if plainly { flash = reveal }
                try? await Task.sleep(for: .milliseconds(50))
                proxy.scrollTo(reveal.rowID, anchor: .center)
                if !plainly { flash = reveal }
            }
        }
        // A page's undo toasts show over the visible pane, not at the bottom of a long page; and leave
        // with the page that raised them, as its Undo goes with it.
        .undoToastAnchor()
        // A new page starts at the top: each page gets its own scroller.
        .id(selectedPane?.id)
        .environment(\.settingsFlash, flash)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.dsBackground)
        .dsToolbarBand(showsDivider: isScrolled)
        // Each page starts at the top, with its own scroller.
        .onChange(of: selectedPane?.id) { isScrolled = false }
        .task(id: pane) {
            if plainly, let pane, SettingsPageMap.destination(pane) != pane {
                reveal = SettingsReveal(rowID: SettingsPageMap.sectionID(pane))
            }
        }
    }

    private func open(_ item: SettingsSearchIndex.Item) {
        selection.wrappedValue = item.paneID
        query = ""
        if let rowID = item.rowID {
            reveal = SettingsReveal(rowID: rowID)
        }
    }

    private func close() {
        pane = nil
    }
}

#if DEBUG
#Preview("Settings") {
    DSPreviewPair {
        SettingsScreen(pane: .constant(.general))
            .frame(width: 1000, height: 640)
    }
    .environment(SettingsPreviewFixtures.registry())
    .environment(SettingsPresentation())
}

#Preview("Plainly - Settings frame") {
    DSPreviewPair {
        SettingsScreen(pane: .constant(.general))
            .frame(width: 1000, height: 900)
    }
    .environment(SettingsPreviewFixtures.registry())
    .environment(SettingsPresentation())
    .environment(\.experimentStore, SettingsPreviewFixtures.plainly())
}
#endif
