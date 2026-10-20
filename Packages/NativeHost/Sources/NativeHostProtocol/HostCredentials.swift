import ACP
import Foundation

// Signing agents in on a host nobody sits at (docs/agents.md, "Signing in on a host with no
// screen"): keys the host keeps for an agent's methods, the page and code of a sign-in that waits
// on the user, and checking again after the user signed in some other way. `HostAgent` carries
// the state: `authMethods`, `signInLink`, `authStatus` and `savedCredentials`.

extension HostProtocol.Method {
    /// Saves a key for one of an agent's methods (`AuthMethod.takesSecret`) and signs in with it.
    /// Needs `ClientGrants.manageHost`. Answers with the agent.
    public static let setAgentCredential = "_native/agents/credentials/set"
    /// Forgets a saved key and stops the agent using it. Needs `manageHost`. Answers with the agent.
    public static let removeAgentCredential = "_native/agents/credentials/remove"
    /// Restarts the agent if none of its sessions is working, and asks again whether it's signed
    /// in. Answers with the agent; a working agent is `busy`.
    public static let checkAgentSignIn = "_native/agents/check_sign_in"
    /// Ends a sign-in waiting on the user (`HostAgent.signInLink`); its `authenticate` then fails.
    public static let cancelAgentSignIn = "_native/agents/cancel_sign_in"
}

/// `_native/agents/credentials/set`.
public struct SetAgentCredentialParams: Codable, Sendable {
    public var agentID: String
    /// One of the agent's `authMethods` that takes a key.
    public var methodID: String
    /// The key or token. The host keeps it in its keychain and never logs, journals or sends it.
    public var secret: String

    public init(agentID: String, methodID: String, secret: String) {
        self.agentID = agentID
        self.methodID = methodID
        self.secret = secret
    }
}

extension SetAgentCredentialParams: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "SetAgentCredentialParams(agentID: \(agentID), methodID: \(methodID), secret: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(self, children: ["agentID": agentID, "methodID": methodID])
    }
}

/// `_native/agents/credentials/remove`.
public struct AgentCredentialParams: Codable, Sendable {
    public var agentID: String
    public var methodID: String

    public init(agentID: String, methodID: String) {
        self.agentID = agentID
        self.methodID = methodID
    }
}

/// A sign-in waiting on the user somewhere else: open `url` on any device and enter `code` there.
/// Agents send it as a URL elicitation scoped to their `authenticate` request.
public struct HostSignInLink: Codable, Hashable, Sendable {
    public var url: URL
    /// The code to enter, when `message` has one that looks like it ("ABCD-12345"); `message`
    /// always says it too, since no field in ACP carries it.
    public var code: String?
    /// What the agent says to do, verbatim.
    public var message: String

    public init(url: URL, code: String? = nil, message: String) {
        self.url = url
        self.code = code
        self.message = message
    }

    /// For a link `message` like "Sign in to ChatGPT and enter this code: ABCD-12345".
    public init(url: URL, message: String) {
        self.init(url: url, code: Self.code(in: message), message: message)
    }

    /// The last thing in `message` shaped like a device code: groups of three or more capitals and
    /// digits joined by hyphens.
    static func code(in message: String) -> String? {
        message.matches(of: /\b[A-Z0-9]{3,}(?:-[A-Z0-9]{3,})+\b/).last.map { String($0.output) }
    }
}
