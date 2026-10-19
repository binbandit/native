/// How much room the composer's controls row has. The row takes the roomiest step that fits; each
/// step gives up the least needed labels or controls first, so no control is ever cut off.
enum ComposerControlDensity: CaseIterable {
    /// Every control with its label.
    case regular
    /// Autonomy, the mode and the goal as icons, and context usage as a ring.
    case compact
    /// The mode and the agent's other settings move to the More menu, which also lists the shortcuts.
    case overflow
    /// The model and autonomy move to the More menu too, leaving attach, the goal and More.
    case minimal

    /// Whether pills that can drop their label show only their icon.
    var showsIcons: Bool {
        self != .regular
    }
}
