import Foundation
import Modes

/// One task's mode as the composer shows it (`ModePill`, `ModeMenu`): which mode it's in, the
/// modes it can be in, and putting it in another, all through `TaskModes`.
struct TaskModeControl {
    let session: SessionModel
    var modes: TaskModes = .shared

    var current: Mode {
        modes.mode(of: session)
    }

    var catalog: ModeCatalog {
        modes.catalog(for: session)
    }

    var agentName: String {
        session.agentName
    }

    /// Whether a turn is running, so a new mode's instructions wait for the next message.
    var isWorking: Bool {
        session.phase == .prompting
    }

    /// The name the task's project goes by, for its modes' group.
    var projectName: String? {
        modes.projectRoot(session)?.lastPathComponent
    }

    /// What `mode` can't do as asked on this agent, in sentences.
    func limits(of mode: Mode) -> [String] {
        modes.resolution(of: mode, on: session).limits.map { $0.text(agent: agentName, mode: mode.name) }
    }

    func select(_ id: Mode.ID) {
        Task { await modes.select(id, in: session) }
    }

    /// Reads the project's modes folder again, as the picker opens.
    func refresh() {
        if let root = modes.projectRoot(session) {
            modes.library.refresh(projectAt: root)
        }
    }
}
