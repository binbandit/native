import Observation

/// Which tool rows, exploration groups and long runs of tool work the user opened or closed in one
/// transcript, so a row keeps its state while it's scrolled away: the lazy stack lets go of rows
/// off screen, and their `@State` with them. The transcript puts one in the environment; rows
/// shown anywhere else keep their own state.
@MainActor @Observable
final class TranscriptDisclosures {
    /// Rows open, by id. Tool rows and exploration groups start closed.
    private var opened: Set<String> = []
    /// Long runs of tool work the user closed. They start open.
    private var closedRuns: Set<String> = []

    func isOpen(_ id: String) -> Bool {
        opened.contains(id)
    }

    func toggle(_ id: String) {
        if opened.remove(id) == nil { opened.insert(id) }
    }

    func isRunOpen(_ id: String) -> Bool {
        !closedRuns.contains(id)
    }

    func toggleRun(_ id: String) {
        if closedRuns.remove(id) == nil { closedRuns.insert(id) }
    }

    func openRun(_ id: String) {
        closedRuns.remove(id)
    }
}
