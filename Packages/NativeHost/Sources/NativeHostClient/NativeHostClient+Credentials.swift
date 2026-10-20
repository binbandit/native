import Foundation
import NativeHostProtocol

// Signing agents in on a host nobody sits at (HostCredentials.swift). Each answers with the agent,
// whose `signInLink`, `authStatus` and `savedCredentials` say where things stand.
extension NativeHostClient {
    /// Saves a key or token for one of the agent's methods that takes one and signs in with it. The
    /// host keeps it in its keychain and never sends it back. Needs the host's `manageHost` grant.
    public func setAgentCredential(_ agentID: String, methodID: String, secret: String) async throws -> HostAgent {
        try await call(
            HostProtocol.Method.setAgentCredential,
            SetAgentCredentialParams(agentID: agentID, methodID: methodID, secret: secret))
    }

    /// Forgets the key saved for `methodID` and stops the agent using it. Needs `manageHost`.
    public func removeAgentCredential(_ agentID: String, methodID: String) async throws -> HostAgent {
        try await call(
            HostProtocol.Method.removeAgentCredential, AgentCredentialParams(agentID: agentID, methodID: methodID))
    }

    /// Restarts the agent and asks again whether it's signed in. Fails with `busy` while one of its
    /// sessions is working.
    public func checkAgentSignIn(_ agentID: String) async throws -> HostAgent {
        try await call(HostProtocol.Method.checkAgentSignIn, AgentParams(agentID: agentID))
    }

    /// Ends a sign-in waiting on the user, such as a device code; its `authenticateAgent` then fails.
    public func cancelAgentSignIn(_ agentID: String) async throws -> HostAgent {
        try await call(HostProtocol.Method.cancelAgentSignIn, AgentParams(agentID: agentID))
    }
}
