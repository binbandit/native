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
    @State private var query = ""
    @State private var highlightedResult = 0
    @State private var reveal: SettingsReveal?
    @State private var flash: SettingsReveal?
    @FocusState private var focus: Focus?
    /// At compact widths (iPad split view and slide over) the split view becomes a stack: the nav
    /// first, and picking a page pushes it.
    @State private var compactColumn = NavigationSplitViewColumn.sidebar

    private var panes: [SettingsPane] {
        (SettingsPane.builtIn(registry: registry) + additionalPanes)
            .sorted { ($0.group, $0.order) < ($1.group, $1.order) }
    }

    private var selectedPane: SettingsPane? {
        panes.first { $0.id == pane } ?? panes.first
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
                    .padding(.top, SettingsMetrics.pageTopInset)
                    .padding(.bottom, SettingsMetrics.pageBottomInset)
            }
            .task(id: reveal) {
                guard let reveal else { return }
                // Let a newly selected page lay out before scrolling into it.
                try? await Task.sleep(for: .milliseconds(50))
                proxy.scrollTo(reveal.rowID, anchor: .center)
                flash = reveal
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
