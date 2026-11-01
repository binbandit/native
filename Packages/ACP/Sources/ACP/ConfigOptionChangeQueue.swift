/// ACP config replies replace whole settings snapshots. Queue changes in user order so a reply
/// cannot overwrite a newer choice. Controls that remain enabled can preserve repeated selections;
/// controls that disable pending options reject them by default.
@MainActor
public final class ConfigOptionChangeQueue {
    private var optionCounts: [String: Int] = [:]
    private var tail: Task<Void, Never>?

    public init() {}

    public var isEmpty: Bool { optionCounts.isEmpty }

    public func contains(_ optionID: String) -> Bool { optionCounts[optionID] != nil }

    public func enqueue(
        _ optionID: String, preservingRepeatedSelections: Bool = false,
        operation: @escaping @MainActor () async -> Void
    ) {
        guard preservingRepeatedSelections || !contains(optionID) else { return }
        optionCounts[optionID, default: 0] += 1
        let previous = tail
        tail = Task {
            await previous?.value
            await operation()
            let remaining = optionCounts[optionID, default: 1] - 1
            optionCounts[optionID] = remaining == 0 ? nil : remaining
            if optionCounts.isEmpty { tail = nil }
        }
    }
}
