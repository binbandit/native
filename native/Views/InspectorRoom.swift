import SwiftUI

/// Makes room for a session's inspector without resizing the window: when opening one would make
/// the window wider, the sidebar steps aside, and comes back when the inspector closes unless the
/// user showed or hid it in between. The window provides it; a session view asks before opening.
struct InspectorRoom {
    /// Called just before an inspector `width` wide (its ideal) opens.
    let prepare: (_ width: CGFloat) -> Void
    /// Called once no inspector is open any more.
    let release: () -> Void

    static let none = InspectorRoom(prepare: { _ in }, release: {})
}

extension EnvironmentValues {
    @Entry var inspectorRoom = InspectorRoom.none
}
