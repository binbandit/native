import SwiftUI

/// The few widths goal and workflow screens need that the design system has no token for yet. Kept
/// here, in one place, until they move into `DS.Size`.
enum AutomationMetrics {
    /// The readable column, the same as the transcript's.
    static let columnWidth: CGFloat = 760
    static let goalEditorWidth: CGFloat = 420
    static let pickerWidth: CGFloat = 720
    /// Width of a workflow card in the picker's three-column grid.
    static let cardMinWidth: CGFloat = 200
    /// The inspector beside a run, showing one step's conversation.
    static let inspectorWidth: (min: CGFloat, ideal: CGFloat, max: CGFloat) = (340, 440, 640)
}
