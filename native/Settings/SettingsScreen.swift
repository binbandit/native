import SwiftUI

/// Settings as Conductor shows them: a full-window screen inside the main window, with a nav
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
            set: { pane = $0 }
        )
    }

    var body: some View {
        // A split view, like the main window's, keeps the toolbar and window controls where they
        // are and puts Back at the nav's trailing edge, where Conductor has it.
        NavigationSplitView(columnVisibility: .constant(.all)) {
            SettingsNavigation(panes: panes, selection: selection, focus: $focus) {
                SettingsSearchField(
                    query: $query,
                    results: SettingsSearchIndex(panes: panes).results(for: query, limit: SettingsMetrics.resultsLimit),
                    highlighted: $highlightedResult,
                    focus: $focus,
                    onPick: open
                )
            }
            // Removing the sidebar toggle here, rather than on the split view, would drop this width.
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
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .navigationTitle("Settings")
        .background {
            Button("Search Settings") { focus = .search }
                .keyboardShortcut("f")
                .hidden()
        }
        .onExitCommand(perform: close)
        .onChange(of: focus) { _, newValue in
            // Conductor closes the results when you click away from the search.
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
        // A new page starts at the top, as Conductor remounts its scroller per page.
        .id(selectedPane?.id)
        .environment(\.settingsFlash, flash)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.dsBackground)
    }

    private func open(_ item: SettingsSearchIndex.Item) {
        pane = item.paneID
        query = ""
        if let rowID = item.rowID {
            reveal = SettingsReveal(rowID: rowID)
        }
    }

    private func close() {
        pane = nil
    }
}
