import SwiftUI

/// The sidebar column's toolbar: the sidebar toggle and search at the leading edge, next to the window
/// controls, and the update button and back and forward at its trailing edge.
struct RootSidebarToolbar: ToolbarContent {
    @Binding var columnVisibility: NavigationSplitViewVisibility
    let model: AppModel
    let updates: UpdateController?
    let isNightly: Bool

    var body: some ToolbarContent {
        ToolbarItem {
            SidebarCollapseButton(isExpanded: columnVisibility != .detailOnly) {
                withAnimation {
                    columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
                }
            }
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarItem {
            TranscriptSearchToolbarButton()
        }
        .sharedBackgroundVisibility(.hidden)
        if isNightly {
            ToolbarItem {
                NightlyMark()
                    .foregroundStyle(.dsTextTertiary)
            }
            .sharedBackgroundVisibility(.hidden)
        }
        // Pushes the toggle and search to the leading edge, next to the window controls, and
        // back and forward to its trailing edge, by the content they navigate.
        if columnVisibility != .detailOnly || !model.offersTaskPeek {
            ToolbarSpacer(.flexible)
        }
        // The update button: right-aligned before back and forward, and still there when
        // the sidebar is hidden. It shows only when an update needs the user.
        if let updates, updates.showsToolbarButton {
            ToolbarItem {
                UpdateToolbarButton(controller: updates)
            }
            .sharedBackgroundVisibility(.hidden)
        }
        if columnVisibility != .detailOnly {
            ToolbarItem {
                HistoryNavigationButtons(
                    canGoBack: model.canGoBack, canGoForward: model.canGoForward,
                    onBack: model.goBack, onForward: model.goForward)
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }
}
