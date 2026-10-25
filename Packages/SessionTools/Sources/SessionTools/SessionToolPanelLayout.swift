/// Resizing changes where an open side tool appears, without changing the user's selection.
public struct SessionToolPanelLayout: Equatable, Sendable {
    public let docksSidePanel: Bool
    public let docked: SessionToolID?
    public let overlay: SessionToolID?
    public let replacement: SessionToolID?

    public init(
        open: [SessionToolPlace: SessionToolID], availableWidth: Double,
        minimumConversationWidth: Double, panelWidth: Double, replacingConversationWith tool: SessionToolID? = nil
    ) {
        docksSidePanel = availableWidth >= minimumConversationWidth + panelWidth
        docked = docksSidePanel ? open[.side] : nil
        let floating = open[.fact] ?? (docksSidePanel ? nil : open[.side])
        replacement = !docksSidePanel && floating == tool ? floating : nil
        overlay = replacement == nil ? floating : nil
    }
}
