import SwiftUI

/// The sidebar. Its top half follows the reference app: "New Session" and the navigation items other features
/// add, then their accessories (the usage meter). Below a hairline, the projects and their sessions
/// follow the reference app's tree, and its footer holds the agents' health, Help and Settings. Nothing in it
/// is opaque, so the sidebar material shows through everywhere.
///
/// Features extend it through its slots rather than editing it: `navigationItems` adds rows under
/// "New Session" (e.g. Pull Requests), `accessories` adds views under them (e.g. usage), and
/// `taskAccessory` supplies each task row's trailing indicator (context usage by default).
///
/// Keys (docs/keyboard.md): ↑ and ↓ move the selection once the list has focus (clicking a row gives
/// it focus), Return renames the selected session, and it publishes `sidebarReorder` for ⌥⌘↑ / ⌥⌘↓.
struct SidebarView<NavigationItems: View, Accessories: View, TaskAccessory: View>: View {
    @Environment(AppModel.self) private var model
    @FocusState private var isListFocused: Bool

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
                ProjectList(taskAccessory: taskAccessory, select: select)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DS.Space.sm)
                    .padding(.vertical, DS.Space.md)
            }
            .scrollIndicators(.automatic)
            .focusable()
            .focused($isListFocused)
            .focusEffectDisabled()
            .onMoveCommand { direction in
                switch direction {
                case .up: model.selectSession(offset: -1)
                case .down: model.selectSession(offset: 1)
                default: break
                }
            }
            .onKeyPress(.return) {
                guard model.renaming == nil, let selection = model.selection else { return .ignored }
                model.renaming = selection
                return .handled
            }
            .accessibilityLabel("Projects")

            SidebarFooter()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .focusedSceneValue(\.sidebarReorder, reorder)
    }

    private func select(_ key: SessionKey) {
        model.selection = key
        isListFocused = true
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
            navigationItems: { EmptyView() }, accessories: { EmptyView() },
            taskAccessory: { SessionContextUsage(summary: $0) })
    }
}

extension SidebarView where TaskAccessory == SessionContextUsage {
    /// The sidebar with other features' navigation rows and accessories, and the built-in context ring
    /// on task rows.
    init(@ViewBuilder navigationItems: () -> NavigationItems, @ViewBuilder accessories: () -> Accessories) {
        self.init(
            navigationItems: navigationItems, accessories: accessories,
            taskAccessory: { SessionContextUsage(summary: $0) })
    }
}
