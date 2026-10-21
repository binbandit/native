/// What the session screen shows for its tools right now. The rules, so the default screen stays
/// the conversation and the composer:
///
/// - A tool's fact shows while it has one, wherever the tool lives (not when it's off).
/// - A side or workbench tool has a tab while its pane has something in it, or while it's open.
/// - The workbench shows only while it has a tab.
public struct SessionToolLayout: Equatable, Sendable {
    /// Under the title, in the tools' order.
    public let facts: [SessionToolID]
    /// The side panel's tabs.
    public let side: [SessionToolID]
    /// The workbench's tabs; none means no workbench.
    public let workbench: [SessionToolID]

    /// - Parameters:
    ///   - tools: In the order they show.
    ///   - withFacts: Tools that have a fact to show now.
    ///   - withContent: Tools whose pane has something in it now (changes made, a shell open).
    ///   - open: Tools whose pane is open.
    public init(
        tools: [SessionToolSpec], arrangement: SessionToolArrangement, withFacts: Set<SessionToolID>,
        withContent: Set<SessionToolID>, open: Set<SessionToolID>
    ) {
        let placed = tools.map { ($0.id, arrangement.place(of: $0)) }
        let shown = withContent.union(open)
        facts = placed.filter { $0.1 != .off && withFacts.contains($0.0) }.map(\.0)
        side = placed.filter { $0.1 == .side && shown.contains($0.0) }.map(\.0)
        workbench = placed.filter { $0.1 == .workbench && shown.contains($0.0) }.map(\.0)
    }
}
