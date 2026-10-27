/// ACP config replies replace whole settings snapshots. Queue changes in user order so a reply
/// cannot overwrite a newer choice; reject repeated changes to an option until its reply arrives.
@MainActor
public final class ConfigOptionChangeQueue {
    private var optionIDs: Set<String> = []
    private var tail: Task<Void, Never>?

    public init() {}

    public var isEmpty: Bool { optionIDs.isEmpty }

    public func contains(_ optionID: String) -> Bool { optionIDs.contains(optionID) }

    public func enqueue(_ optionID: String, operation: @escaping @MainActor () async -> Void) {
        guard optionIDs.insert(optionID).inserted else { return }
        let previous = tail
        tail = Task {
            await previous?.value
            await operation()
            optionIDs.remove(optionID)
            if optionIDs.isEmpty { tail = nil }
        }
    }
}
