/// How much room the composer's controls row has. The row takes the roomiest step that fits; each
/// step gives up the least needed labels or controls first, so no control is ever cut off.
enum ComposerControlDensity: CaseIterable {
    /// Primary controls with their labels; extra agent settings stay in More at every density.
    case regular
    /// Autonomy, the mode and the goal as icons, and context usage as a ring.
    case compact
    /// The mode moves to the More menu, alongside extra agent settings and keyboard shortcuts.
    case overflow
    /// The model and autonomy move to the More menu too, leaving attach, the goal and More.
    case minimal

    /// Whether pills that can drop their label show only their icon.
    var showsIcons: Bool {
        self != .regular
    }
}
