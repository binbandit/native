import ACP
import Foundation
import NativeHostProtocol

/// What an `AgentLink` knows about signing its agent in, beyond `needsSignIn` and `isSigningIn`
/// (HostCore+Credentials.swift). Clients see it in `HostAgent`.
struct AgentSignInState: Equatable {
    /// The methods the agent advertised the last time it started, kept while it's stopped.
    var advertised: [AuthMethod] = []
    /// A sign-in waiting on the user, with the agent's elicitation to answer when it ends.
    var link: PendingSignInLink?
    /// Who the agent last said it's signed in as, and which process said it.
    var status: AgentAuthStatus?
    var statusGeneration: Int?
    /// The methods the host keeps a key for, by id.
    var savedCredentials: [String] = []
    /// Set while the agent runs for a `link` sign-in: its `initialize` advertises URL elicitations.
    var advertisesLinks = false

    /// The agent's methods, then what its plugin declares that the agent didn't advertise.
    func authMethods(declared: [AuthMethod]) -> [AuthMethod] {
        let advertisedIDs = Set(advertised.map(\.id))
        return advertised + declared.filter { !advertisedIDs.contains($0.id) }
    }
}

/// A URL elicitation an agent sent for its `authenticate`, waiting for the sign-in to end.
struct PendingSignInLink: Equatable {
    var shown: HostSignInLink
    /// The agent's `elicitation/create` request, answered when the sign-in ends or is cancelled.
    var request: RequestID
    var elicitationID: String?
}
