/// Resizing changes where an open side tool appears, without changing the user's selection.
public struct SessionToolPanelLayout: Equatable, Sendable {
    public let docksSidePanel: Bool
    public let docked: SessionToolID?
    public let overlay: SessionToolID?

    public init(
        open: [SessionToolPlace: SessionToolID], availableWidth: Double,
        minimumConversationWidth: Double, panelWidth: Double
    ) {
        docksSidePanel = availableWidth >= minimumConversationWidth + panelWidth
        docked = docksSidePanel ? open[.side] : nil
        overlay = open[.fact] ?? (docksSidePanel ? nil : open[.side])
    }
}
