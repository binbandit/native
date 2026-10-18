import SwiftUI

/// Makes room for a session's inspector without resizing the window: when opening one would make
/// the window wider, the sidebar steps aside first, and comes back when the inspector closes unless
/// the user showed or hid it in between. The window provides it; a session view opens through it.
struct InspectorRoom {
    /// Runs `open`, which shows an inspector `width` wide (its ideal), once there's room for it.
    let open: (_ width: CGFloat, _ open: @escaping @MainActor () -> Void) -> Void
    /// Called once no inspector is open any more.
    let release: () -> Void

    static let none = InspectorRoom(open: { _, open in open() }, release: {})
}

extension EnvironmentValues {
    @Entry var inspectorRoom = InspectorRoom.none
}

/// The window's side of `InspectorRoom`: opening an inspector never widens the window, so the
/// sidebar steps aside when it must, and comes back when the inspector closes unless the user
/// showed or hid it meanwhile or the window is now too narrow to hold it.
@MainActor
final class SidebarInspectorRoom {
    let window = PlatformWindowRoom()
    /// The window's minimum widths while the sidebar is aside: with the sidebar, and with neither it
    /// nor the inspector.
    private var aside: (withSidebar: CGFloat, without: CGFloat)?

    func room(sidebar: Binding<NavigationSplitViewVisibility>) -> InspectorRoom {
        InspectorRoom(
            open: { [self] width, open in
                guard sidebar.wrappedValue != .detailOnly, window.wouldGrow(adding: width) else { return open() }
                aside = (window.minWidth, 0)
                sidebar.wrappedValue = .detailOnly
                // The window's minimum width drops only once the sidebar has gone; an inspector opened
                // before then still widens it.
                Task {
                    await window.waitUntil { !window.wouldGrow(adding: width) }
                    aside?.without = window.minWidth
                    open()
                }
            },
            release: { [self] in
                guard let widths = aside, sidebar.wrappedValue == .detailOnly else { return }
                aside = nil
                // Likewise the inspector counts toward the minimum until it has gone.
                Task {
                    await window.waitUntil { window.minWidth <= widths.without }
                    guard sidebar.wrappedValue == .detailOnly, window.width >= widths.withSidebar else { return }
                    withAnimation { sidebar.wrappedValue = .all }
                }
            }
        )
    }

    /// The user showed the sidebar again: it's theirs, and stays as they leave it.
    func sidebarChanged(to visibility: NavigationSplitViewVisibility) {
        if visibility != .detailOnly { aside = nil }
    }
}
