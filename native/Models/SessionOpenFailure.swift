import ACP
import Foundation

/// Why a listed task couldn't be opened before Native had a model for it, so its place shows that
/// rather than a loader that never ends.
struct SessionOpenFailure: Hashable {
    enum Reason: Hashable {
        /// No agent of that kind is set up any more (its plugin was turned off or removed).
        case agentMissing
        /// The agent stopped before the task opened.
        case notRunning
        /// The agent lists its past tasks but can't load one back.
        case cannotLoad
        /// Anything else, with the error in `details`.
        case failed
    }

    let reason: Reason
    /// The agent's name, or its id when Native no longer knows it.
    let agent: String
    let details: String?

    init(_ reason: Reason, agent: String, details: String? = nil) {
        self.reason = reason
        self.agent = agent
        self.details = details
    }

    init(_ error: any Error, agent: String) {
        let details = error.localizedDescription.withoutTerminalEscapes
        switch error {
        case SessionLauncher.LaunchError.cannotLoad: self.init(.cannotLoad, agent: agent)
        case SessionLauncher.LaunchError.agentUnavailable: self.init(.notRunning, agent: agent, details: details)
        default: self.init(.failed, agent: agent, details: details)
        }
    }
}
