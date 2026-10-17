import SwiftUI

extension FocusedValues {
    /// The frontmost window's Settings page, nil while Settings is closed. The ⌘, command toggles
    /// it; anything that wants to open a specific page sets it.
    @Entry var settingsPane: Binding<SettingsPane.ID?>?
}
