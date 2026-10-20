import ACP
import Foundation

// Agents as the host runs them: their status, starting and stopping them, signing in, and the
// agent-level ACP calls clients make (listing and deleting the agent's saved sessions).

extension HostProtocol.Method {
    public static let listAgents = "_native/agents/list"
    public static let startAgent = "_native/agents/start"
    public static let stopAgent = "_native/agents/stop"
    public static let restartAgent = "_native/agents/restart"
    public static let authenticateAgent = "_native/agents/authenticate"
    /// Wraps ACP's `session/list`.
    public static let listAgentSessions = "_native/agents/list_sessions"
    /// Wraps ACP's `session/delete`.
    public static let deleteAgentSession = "_native/agents/delete_session"
    /// Host → client: an agent's status changed.
    public static let agentChanged = "_native/agents/changed"
}

public enum HostAgentState: String, WireEnum {
    /// Not running, and fine that way: it starts when something needs it. An agent that exits on its
    /// own comes back here too.
    case stopped
    case starting
    case ready
    /// It launched but never got going; `problem` says why, with what it logged.
    case failed
    /// Its command isn't on the user's PATH; `problem` names it.
    case notInstalled
    case unknown
}

/// One agent as the host sees it.
public struct HostAgent: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var state: HostAgentState
    /// For `failed`, the error and the end of the agent's stderr; for `notInstalled`, the command.
    public var problem: String?
    /// The agent's ACP `initialize` result, verbatim, while it runs: its info, capabilities, sign-in
    /// methods and `_meta` (steering). Decode it with ACP's `InitializeResponse`.
    public var initialize: JSONValue?
    /// The launched process (`env`, which execs the agent), while it runs.
    public var processID: Int32?
    /// The spec the running process was started from, to tell when a changed spec needs a restart.
    public var launchedSpec: AgentSpec?
    /// The agent turned a request away until the user signs in (ACP `auth_required`).
    public var needsSignIn: Bool
    public var isSigningIn: Bool
    /// The ways to sign it in: what it advertised in `initialize`, plus what its plugin declares
    /// for it (`AgentSpec.authMethods`). Nil from hosts older than these (HostCredentials.swift).
    public var authMethods: [AuthMethod]?
    /// While a sign-in waits on the user: the page to open and the code to enter there.
    public var signInLink: HostSignInLink?
    /// Who the agent last said it's signed in as, when it reports that.
    public var authStatus: AgentAuthStatus?
    /// The methods the host keeps a key for, by id. Never the keys.
    public var savedCredentials: [String]?

    public init(
        id: String, name: String, state: HostAgentState, problem: String? = nil, initialize: JSONValue? = nil,
        processID: Int32? = nil, launchedSpec: AgentSpec? = nil, needsSignIn: Bool = false, isSigningIn: Bool = false,
        authMethods: [AuthMethod]? = nil, signInLink: HostSignInLink? = nil, authStatus: AgentAuthStatus? = nil,
        savedCredentials: [String]? = nil
    ) {
        self.id = id
        self.name = name
        self.state = state
        self.problem = problem
        self.initialize = initialize
        self.processID = processID
        self.launchedSpec = launchedSpec
        self.needsSignIn = needsSignIn
        self.isSigningIn = isSigningIn
        self.authMethods = authMethods
        self.signInLink = signInLink
        self.authStatus = authStatus
        self.savedCredentials = savedCredentials
    }
}

public struct AgentParams: Codable, Sendable {
    public var agentID: String

    public init(agentID: String) {
        self.agentID = agentID
    }
}

/// `_native/agents/stop` stops an agent only when none of its sessions is working (a turn, a
/// recovery, a queue waiting to go out, a hidden command); `stopped` says whether it did.
public struct StopAgentResult: Codable, Sendable {
    public var stopped: Bool
    public var agent: HostAgent

    public init(stopped: Bool, agent: HostAgent) {
        self.stopped = stopped
        self.agent = agent
    }
}

public struct AuthenticateAgentParams: Codable, Sendable {
    public var agentID: String
    /// One of the `authMethods` in the agent's `initialize` result.
    public var methodID: String

    public init(agentID: String, methodID: String) {
        self.agentID = agentID
        self.methodID = methodID
    }
}

/// Lists the agent's saved sessions, starting the agent if needed. The result is ACP's
/// `ListSessionsResponse`, verbatim.
public struct ListAgentSessionsParams: Codable, Sendable {
    public var agentID: String
    public var cwd: String?
    public var cursor: String?

    public init(agentID: String, cwd: String? = nil, cursor: String? = nil) {
        self.agentID = agentID
        self.cwd = cwd
        self.cursor = cursor
    }
}

/// Deletes a session from the agent's own store. A host session holding it is closed too.
public struct DeleteAgentSessionParams: Codable, Sendable {
    public var agentID: String
    public var agentSessionID: SessionID

    public init(agentID: String, agentSessionID: SessionID) {
        self.agentID = agentID
        self.agentSessionID = agentSessionID
    }
}

public struct AgentChangedNotification: Codable, Sendable {
    public var agent: HostAgent

    public init(agent: HostAgent) {
        self.agent = agent
    }
}
