import Observation

/// Disclosure choices for one session, owned by its model rather than a transient transcript view.
/// Every transcript style shares these choices across scrolling and session switches.
@MainActor @Observable
public final class TranscriptDisclosures {
    public init() {}

    /// Rows open, by id. Tool rows and exploration groups start closed.
    private var opened: Set<String> = []
    /// Long runs of tool work the user opened. They start closed.
    private var openedRuns: Set<String> = []
    /// Earlier turns the user opened back up.
    public var unfoldedTurns: Set<TranscriptTurn.ID> = []

    public func isOpen(_ id: String, hasPendingApproval: Bool = false) -> Bool {
        hasPendingApproval || opened.contains(id)
    }

    public func toggle(_ id: String) {
        if opened.remove(id) == nil { opened.insert(id) }
    }

    /// Approval visibility is derived, so answering returns to the user's unchanged choice.
    public func isRunOpen(_ id: String, hasPendingApproval: Bool = false) -> Bool {
        hasPendingApproval || openedRuns.contains(id)
    }

    public func toggleRun(_ id: String) {
        if openedRuns.remove(id) == nil { openedRuns.insert(id) }
    }

    public func openRun(_ id: String) {
        openedRuns.insert(id)
    }
}
