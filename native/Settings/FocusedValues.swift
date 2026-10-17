import SwiftUI

extension FocusedValues {
    /// The session in the frontmost window's detail pane, for menu commands that act on it
    /// (stop, focus the composer, cycle the permission mode).
    @Entry var activeSession: SessionModel?
}
