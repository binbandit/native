import ACP
import Foundation

// What the host tells clients without being asked: session events and summaries, and the activity
// journal ("while you were away").

public struct SessionEventNotification: Codable, Sendable {
    public var sessionID: HostSessionID
    public var event: HostEvent

    public init(sessionID: HostSessionID, event: HostEvent) {
        self.sessionID = sessionID
        self.event = event
    }
}

public struct SessionChangedNotification: Codable, Sendable {
    public var summary: HostSessionSummary

    public init(summary: HostSessionSummary) {
        self.summary = summary
    }
}

/// Something that happened to a session, kept so the user can see what went on while they were
/// away: finished turns, approvals asked for, interruptions recovered from.
public struct ActivityEntry: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, WireEnum {
        case turnFinished
        case turnFailed
        case approvalNeeded
        /// The agent asked the user a question (a form to fill in).
        case questionAsked
        case recovered
        /// The host started with work to pick up, or after its previous run ended badly
        /// (`previousRun` says how).
        case hostStarted
        /// Turns the user stopped with Quit Native and Stop Agents.
        case stopped
        /// A client asked to install an update (`subject` names the device).
        case updateRequested
        /// A new standalone build didn't come up, so the host went back to the one before.
        case updateRolledBack
        case unknown
    }

    /// How the host's previous run ended, for `hostStarted`.
    public enum RunEnding: String, WireEnum {
        /// Stopped on purpose (Quit Native and Stop Agents, or a development host's idle exit).
        case stopped
        /// Killed or crashed; launchd started it again.
        case crashed
        /// Restarted onto a newer build.
        case updated
        /// The Mac restarted or the user logged out.
        case systemRestarted
        case unknown
    }

    public var id: Int64
    public var at: Date
    public var sessionID: HostSessionID?
    /// The session's agent and the agent's id for it, so an entry still leads to its task after the
    /// host stopped tracking the session.
    public var agentID: String?
    public var agentSessionID: SessionID?
    public var kind: Kind
    /// The session's title or agent, at the time.
    public var subject: String?
    public var detail: String?
    public var recovery: RecoveryNote?
    public var previousRun: RunEnding?

    public init(
        id: Int64, at: Date, sessionID: HostSessionID?, agentID: String? = nil, agentSessionID: SessionID? = nil,
        kind: Kind, subject: String? = nil, detail: String? = nil, recovery: RecoveryNote? = nil,
        previousRun: RunEnding? = nil
    ) {
        self.id = id
        self.at = at
        self.sessionID = sessionID
        self.agentID = agentID
        self.agentSessionID = agentSessionID
        self.kind = kind
        self.subject = subject
        self.detail = detail
        self.recovery = recovery
        self.previousRun = previousRun
    }
}
