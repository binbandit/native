import SwiftUI

/// The sidebar. Its top half follows the reference app: "New Session" and the navigation items other features
/// add, then their accessories (the usage meter). Below a hairline, the projects and their sessions
/// follow the reference app's tree, and its footer holds Help and Settings. Nothing in it
/// is opaque, so the sidebar material shows through everywhere.
///
/// Features extend it through its slots rather than editing it: `navigationItems` adds rows under
/// "New Session" (e.g. Pull Requests), `accessories` adds views under them (e.g. usage),
/// and `taskAccessory` supplies each task row's trailing indicator (context usage by default).
///
/// Keys (docs/keyboard.md): ↑ and ↓ move the selection once the list has focus, keeping focus here;
/// clicking a row means "work here", so it focuses that session's composer. Return renames the
/// selected session, and the sidebar publishes `sidebarReorder` for ⌥⌘↑ / ⌥⌘↓.
struct SidebarView<NavigationItems: View, Accessories: View, TaskAccessory: View>: View {
    @Environment(AppModel.self) private var model
    @FocusState private var isListFocused: Bool
    @AppStorage("sidebar.showsOnlyNeedsYou") private var showsOnlyNeedsYou = false

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
        VStack(alignment: .leading, spacing: 0) {
            // the reference app's primary nav group: 6pt insets, 2pt between rows.
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                NewSessionItem()
                navigationItems
                accessories
            }
            .padding(DS.Space.sm)
            SeparatorLine()
                .padding(.horizontal, DS.Space.lg)

            ScrollView {
                ProjectList(taskAccessory: taskAccessory, showsOnlyNeedsYou: $showsOnlyNeedsYou, select: select)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DS.Space.sm)
                    .padding(.vertical, DS.Space.md)
            }
            .scrollIndicators(.automatic)
            .focusable()
            .focused($isListFocused)
            .focusEffectDisabled()
            .onKeyPress(.upArrow) {
                model.selectSession(offset: -1)
                return .handled
            }
            .onKeyPress(.downArrow) {
                model.selectSession(offset: 1)
                return .handled
            }
            .onKeyPress(.return) {
                guard model.renaming == nil, let selection = model.selection else { return .ignored }
                model.renaming = selection
                return .handled
            }
            .accessibilityLabel("Projects")
            .onAppear { LaunchMetrics.markOnScreen(.sidebarInteractive) }

            SidebarFooter()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .focusedSceneValue(\.sidebarReorder, reorder)
        .focusedSceneValue(\.sidebarNeedsYouFilter, $showsOnlyNeedsYou)
    }

    /// A row was clicked or tapped, which means "work here": select it and focus its composer once
    /// the session is open. Keyboard navigation selects without this, so focus stays in the list.
    private func select(_ key: SessionKey) {
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
