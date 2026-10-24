/// Keeps a Settings list's position until its replacement detail has gone and the list is laid out.
public struct SettingsDetailScrollState: Sendable {
    private var savedOffset: Double?
    private var isReturning = false

    public init() {}

    public mutating func openDetail(at offset: Double) {
        if savedOffset == nil { savedOffset = offset }
        isReturning = false
    }

    public mutating func returnToList() {
        isReturning = savedOffset != nil
    }

    /// Consuming this before layout would clamp the offset to the shorter detail's scroll range.
    public mutating func listDidLayout() -> Double? {
        guard isReturning else { return nil }
        defer { discard() }
        return savedOffset
    }

    /// Search, a different page, and closing Settings own their next destination.
    public mutating func discard() {
        savedOffset = nil
        isReturning = false
    }
}
