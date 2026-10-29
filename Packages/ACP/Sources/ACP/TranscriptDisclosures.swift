import Observation

/// Disclosure choices for one session, owned by its model rather than a transient transcript view.
/// Every transcript style shares these choices across scrolling and session switches.
@MainActor @Observable
public final class TranscriptDisclosures {
    public init() {}

    /// Tool rows and groups of tool work open, by id. They start closed.
    private var opened: Set<String> = []
    /// Earlier turns the user opened back up.
    public var unfoldedTurns: Set<TranscriptTurn.ID> = []

    public func isOpen(_ id: String) -> Bool {
        opened.contains(id)
    }

    public func toggle(_ id: String) {
        if opened.remove(id) == nil { opened.insert(id) }
    }

    /// Opens a row or group without closing it if it's open already, as revealing a search result
    /// inside it does.
    public func open(_ id: String) {
        opened.insert(id)
    }
}
