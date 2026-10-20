/// One of a tool's own tabs in a place's strip: a shell, a run.
struct SessionToolTabItem: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    var accessory: SessionToolFact.Accessory?
    /// Whether it's the one the tool shows when it's open.
    let isSelected: Bool
    let select: () -> Void
    /// Closes it (a shell's tab), from its menu and its ✕ while selected.
    var close: (() -> Void)?
}
