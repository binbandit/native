import SwiftUI

/// A page's links use Settings' containing scroll view, including its search reveal targets.
struct SettingsScrollAction {
    var scroll: (SettingsRowID, UnitPoint) -> Void

    func callAsFunction(_ id: SettingsRowID, _ anchor: UnitPoint) { scroll(id, anchor) }
}
