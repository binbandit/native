import Experiments
import SwiftUI
import TaskList

/// The sidebar. Its top half holds "New Session" and the navigation items other features add, then
/// their accessories (the usage meter). Below a hairline, the projects and their sessions form a
/// tree, and its footer holds Help and Settings. Nothing in it
/// is opaque, so the sidebar material shows through everywhere.
///
/// Features extend it through its slots rather than editing it: `navigationItems` adds rows under
/// "New Session" (e.g. Pull Requests), `accessories` adds views under them (e.g. usage),
/// and `taskAccessory` supplies each task row's trailing indicator (context usage by default).
///
/// Keys (docs/keyboard.md): ↑ and ↓ move the selection once the list has focus, keeping focus here;
/// clicking a row means "work here", so it focuses that session's composer. ⌘-click and ⇧-click
/// pick tasks for bulk actions instead, ⌘A picks the project's, and Escape lets them go. Return
/// renames the selected session, and the sidebar publishes `sidebarReorder` for ⌥⌘↑ / ⌥⌘↓.
///
/// Each window keeps its own filters (`TaskFilter`, restored on relaunch) and its own picks.
struct SidebarView<NavigationItems: View, Accessories: View, TaskAccessory: View>: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    @Environment(\.sidebarTaskInsights) private var insights
    @FocusState private var isListFocused: Bool
    @SceneStorage("sidebar.taskFilter") private var storedFilter = ""
    @State private var folding = SidebarDayFolding()
    @State private var selection = SidebarSelectionModel()
    @Experiment(.sidebarNext) private var usesSidebarNext

    private let navigationItems: NavigationItems
    private let accessories: Accessories
    private let taskAccessory: (SessionSummary) -> TaskAccessory

    init(
        @ViewBuilder navigationItems: () -> NavigationItems,
        @ViewBuilder accessories: () -> Accessories,
        @ViewBuilder taskAccessory: @escaping (SessionSummary) -> TaskAccessory
    ) {
        self.navigationItems = navigationItems()
        self.accessories = accessories()
        self.taskAccessory = taskAccessory
    }

    var body: some View {
        let filter = self.filter
        let listing = SidebarListing(
            model: model, filter: filter, insights: insights, folding: usesSidebarNext ? folding : nil,
            now: DSMinuteClock.shared.now)
        VStack(alignment: .leading, spacing: 0) {
            // The primary nav group: 6pt insets, 2pt between rows.
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                NewSessionItem()
                navigationItems
                accessories
            }
            .padding(.horizontal, DS.Space.sm)
            .padding(.top, DS.Space.sm)
            .padding(.bottom, usesSidebarNext ? DS.Space.xxs : DS.Space.sm)
            if !usesSidebarNext {
                SeparatorLine().padding(.horizontal, DS.Space.lg)
            }

            ScrollView {
                ProjectList(
                    listing: listing, taskAccessory: taskAccessory, filter: filterBinding, selection: selection,
                    select: select, folding: folding
                )
                .environment(\.sidebarAllInView, usesSidebarNext)
                .environment(\.oldestTaskAskID, usesSidebarNext ? model.oldestTaskAsk?.id : nil)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, usesSidebarNext ? DS.Sidebar.inset : DS.Space.sm)
                .padding(.vertical, usesSidebarNext ? 0 : DS.Space.md)
            }
            .scrollIndicators(.automatic)
            .focusable()
            .focused($isListFocused)
            .focusEffectDisabled()
            .onKeyPress(.upArrow) {
                model.selectSession(offset: -1, in: usesSidebarNext ? listing.order : nil)
                return .handled
            }
            .onKeyPress(.downArrow) {
                model.selectSession(offset: 1, in: usesSidebarNext ? listing.order : nil)
                return .handled
            }
            .onKeyPress(.space) {
                guard usesSidebarNext, model.renaming == nil, let key = model.selection else { return .ignored }
                model.peekTask(key)
                return .handled
            }
            .onKeyPress(.return) {
                guard model.renaming == nil, let selection = model.selection else { return .ignored }
                model.renaming = selection
                return .handled
            }
            // ⌘A picks every task in the open task's project; Escape lets the picks go.
            .onKeyPress(characters: ["a"]) { press in
                guard press.modifiers == .command else { return .ignored }
                let targets = model.selectAllTargets(after: selection)
                guard !targets.isEmpty else { return .ignored }
                selection.selectAll(targets)
                return .handled
            }
            .onKeyPress(.escape) {
                guard selection.isActive else { return .ignored }
                selection.clear()
                return .handled
            }
            .accessibilityLabel("Projects")
            .onAppear { LaunchMetrics.markOnScreen(.sidebarInteractive) }
            .confirmationDialog(
                "Delete “\(selection.deletionRequest.map(model.titleOfSession) ?? "")”?",
                isPresented: Binding(
                    get: { selection.deletionRequest != nil },
                    set: { if !$0 { selection.deletionRequest = nil } }),
                presenting: selection.deletionRequest
            ) { key in
                Button("Delete Task", role: .destructive) {
                    model.deleteSession(key, undoManager: undoManager)
                }
            } message: { key in
                let agent = model.runtime(key.agent)?.agent.displayName ?? "the agent"
                Text(
                    "Its history goes from Native and, if \(agent) supports it, from \(agent) too. You can undo for a few seconds. To keep it out of sight instead, archive it."
                )
            }

            if selection.isActive {
                SidebarSelectionBar(selection: selection)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            SidebarFooter()
        }
        .background(usesSidebarNext ? Color.dsSidebarSolid : Color.clear)
        .animation(.dsQuick, value: selection.isActive)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.sidebarSelection, selection)
        .onModifierKeysChanged(mask: [.command, .shift]) { _, modifiers in
            selection.modifiers = modifiers
        }
        .onChange(of: model.selection, initial: true) { _, key in
            guard usesSidebarNext, let key,
                let group = listing.groups.first(where: { $0.earlier.contains { $0.id == key } })
            else { return }
            folding.setExpanded(group.project.id, true)
        }
        .onChange(of: listing.groups.flatMap(\.earlier).map(\.id)) {
            guard usesSidebarNext, let key = model.selection,
                let group = listing.groups.first(where: { $0.earlier.contains { $0.id == key } })
            else { return }
            folding.setExpanded(group.project.id, true)
        }
        .onChange(of: listing.order, initial: true) { _, order in
            selection.update(order: order)
        }
        .onChange(of: filter, initial: true) { trackArchiveOrder() }
        .onChange(of: usesSidebarNext) { trackArchiveOrder() }
        .onChange(of: insights) { trackArchiveOrder() }
        // Rows a filter hides never load their checkout, so look up what the checkout filters ask
        // about when they're turned on.
        .task(id: filter.requiresUncommittedChanges || filter.requiresPullRequest) {
            guard filter.requiresUncommittedChanges || filter.requiresPullRequest else { return }
            await insights.prepare(model.projects.all.flatMap { model.allSessions(in: $0.id) })
        }
        .confirmationDialog(
            "Delete \(selection.keys.count) Tasks?", isPresented: Bindable(selection).isConfirmingDelete
        ) {
            Button("Delete \(selection.keys.count) Tasks", role: .destructive) {
                let keys = selection.keys
                selection.clear()
                model.deleteSessions(keys, undoManager: undoManager)
            }
        } message: {
            Text(
                "Their history goes from Native and, where the agent supports it, from the agent too. You can undo for a few seconds. To keep them out of sight instead, archive them."
            )
        }
        .focusedSceneValue(\.sidebarReorder, reorder)
        .focusedSceneValue(\.sidebarNeedsYouFilter, needsYouBinding)
        .focusedSceneValue(\.sidebarSelection, selection)
    }

    private func trackArchiveOrder() {
        let model = model
        let filter = filter
        let insights = insights
        let folding = usesSidebarNext ? folding : nil
        // Query live state: a rapid Undo/Redo can run before the sidebar redraws restored tasks.
        selection.setArchiveOrder { [weak model] in
            guard let model else { return [] }
            return SidebarListing(model: model, filter: filter, insights: insights, folding: folding).order
        }
        model.setArchiveNavigationOrder(selection)
    }

    /// The window's filters, kept in its scene storage so each window restores its own.
    private var filter: TaskFilter {
        storedFilter.data(using: .utf8).flatMap { try? JSONDecoder().decode(TaskFilter.self, from: $0) }
            ?? TaskFilter()
    }

    private var filterBinding: Binding<TaskFilter> {
        Binding(
            get: { filter },
            set: { newValue in
                let data = (try? JSONEncoder().encode(newValue)) ?? Data()
                storedFilter = newValue == TaskFilter() ? "" : String(decoding: data, as: UTF8.self)
            }
        )
    }

    /// The Needs You filter alone, for its command (⌥⌘J).
    private var needsYouBinding: Binding<Bool> {
        Binding(
            get: { filter.statuses.contains(.needsYou) },
            set: { isOn in
                var filter = filter
                if isOn != filter.statuses.contains(.needsYou) { filter.toggle(.needsYou) }
                filterBinding.wrappedValue = filter
            }
        )
    }

    /// A row was clicked or tapped, which means "work here": select it and focus its composer once
    /// the session is open. Keyboard navigation selects without this, so focus stays in the list.
    /// With ⌘ or ⇧ held, or in select mode, the click picks the row for bulk actions instead.
    private func select(_ key: SessionKey) {
        if selection.handleClick(on: key, current: model.selection) { return }
        model.selection = key
        Task {
            await model.loadSession(key)
            model.session(key)?.wantsComposerFocus = true
        }
    }

    private var reorder: SidebarReorder {
        SidebarReorder(
            canMove: { direction in model.sidebarMoveTarget.map { model.canMove($0, direction) } ?? false },
            move: { direction in model.sidebarMoveTarget.map { model.move($0, direction) } }
        )
    }
}

extension SidebarView
where NavigationItems == EmptyView, Accessories == EmptyView, TaskAccessory == SessionContextUsage {
    /// The sidebar with nothing from other features, and the built-in context ring on task rows.
    init() {
        self.init(
            navigationItems: { EmptyView() },
            accessories: { EmptyView() },
            taskAccessory: { SessionContextUsage(summary: $0) }
        )
    }
}

extension SidebarView where TaskAccessory == SessionContextUsage {
    /// The sidebar with other features' navigation rows and accessories, and the built-in context ring
    /// on task rows.
    init(
        @ViewBuilder navigationItems: () -> NavigationItems,
        @ViewBuilder accessories: () -> Accessories
    ) {
        self.init(
            navigationItems: navigationItems,
            accessories: accessories,
            taskAccessory: { SessionContextUsage(summary: $0) }
        )
    }
}

#if DEBUG
#Preview("Sidebar") {
    DSPreviewPair {
        SidebarView()
            .frame(width: DS.Size.sidebarWidth, height: 720)
    }
    .sidebarPreviewEnvironment(AppModel.preview())
}

#Preview("Sidebar - Starting task and a problem") {
    DSPreviewPair {
        SidebarView()
            .frame(width: DS.Size.sidebarWidth, height: 720)
    }
    .sidebarPreviewEnvironment(SidebarPreviewFixtures.troubledApp())
}

#Preview("Sidebar - No projects") {
    DSPreviewPair {
        SidebarView()
            .frame(width: DS.Size.sidebarWidth, height: 480)
    }
    .sidebarPreviewEnvironment(AppModel.preview(.empty))
}
#endif
