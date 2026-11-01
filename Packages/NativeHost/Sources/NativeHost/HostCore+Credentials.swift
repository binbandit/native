import ACP
import Foundation
import NativeHostProtocol

// Signing agents in on a host nobody sits at (docs/agents.md, "Signing in on a host with no
// screen"). Keys: the host keeps them (`HostCredentials`) and starts the agent with an
// `environment` method's variable set, or hands an `apiKey` method's key to `authenticate`. Links:
// a device code arrives as a URL elicitation scoped to `authenticate`, shown in
// `HostAgent.signInLink` until the sign-in ends. Checking again: a restart, then the agent's
// `_auth/status_update`. A key goes nowhere but to its agent: never logged, journaled or sent to
// clients, which only see which methods have one.
extension HostCore {
    // MARK: - Signing in

    /// Signs the agent in with one of its methods. The agent may open a browser where it runs and
    /// wait, or send a page and code for the user (`signInLink`), so this can take a while. A `link`
    /// method the agent doesn't offer yet (agents offer those only to clients that open links) runs
    /// in a launch that advertises them, between two restarts.
    func authenticateAgent(_ params: AuthenticateAgentParams) async throws -> HostAgent {
        let link = try await readyAgent(params.agentID)
        let method = link.authMethods.first { $0.id == params.methodID }
        if method?.kind == .link, !link.signIn.advertised.contains(where: { $0.id == params.methodID }) {
            try await signInWithLink(params.methodID, of: link)
        } else {
            try await authenticate(link, methodID: params.methodID)
        }
        return link.hostAgent
    }

    /// Restarts the agent so it offers link sign-ins, signs in, and restarts it as before, unless a
    /// session started working on it meanwhile: then it keeps running until its next restart.
    private func signInWithLink(_ methodID: String, of link: AgentLink) async throws {
        try requireIdle(link, to: "Sign in")
        link.signIn.advertisesLinks = true
        do {
            try await restart(link)
            guard link.signIn.advertised.contains(where: { $0.id == methodID }) else {
                let name = link.authMethods.first { $0.id == methodID }?.name ?? methodID
                throw RPCError(
                    code: -32602,
                    message: "\(link.spec.name) didn't offer \(name) when asked. This version may not support it.")
            }
            try await authenticate(link, methodID: methodID)
        } catch {
            await stopAdvertisingLinks(link)
            throw error
        }
        await stopAdvertisingLinks(link)
    }

    private func stopAdvertisingLinks(_ link: AgentLink) async {
        link.signIn.advertisesLinks = false
        guard workingSessions(of: link) == 0 else { return }
        try? await restart(link)
    }

    /// Sends `authenticate` and waits. A link the agent showed meanwhile goes when it ends.
    private func authenticate(_ link: AgentLink, methodID: String, apiKey: String? = nil) async throws {
        guard let peer = link.peer else { throw HostError.agentUnavailable(link.spec.name) }
        link.isSigningIn = true
        do {
            _ = try await peer.request(
                AuthenticateRequest.method, AuthenticateRequest(methodId: methodID, apiKey: apiKey), as: JSONValue.self)
        } catch {
            link.isSigningIn = false
            endSignInLink(of: link, answer: .cancel)
            throw error
        }
        link.isSigningIn = false
        endSignInLink(of: link, answer: .accept(content: [:]))
        link.needsSignIn = false
    }

    /// Ends a sign-in waiting on the user: the link's elicitation is answered `cancel`, so the agent
    /// gives up and its `authenticate` fails. One waiting on a browser where the agent runs ends only
    /// with the agent, so that one restarts it.
    func cancelAgentSignIn(_ agentID: String) async throws -> HostAgent {
        guard let link = agents[agentID] else { throw HostError.unknownAgent(agentID) }
        if link.signIn.link != nil {
            endSignInLink(of: link, answer: .cancel)
        } else if link.isSigningIn {
            try requireIdle(link, to: "Cancel the sign-in")
            try await restart(link)
        }
        return link.hostAgent
    }

    /// Restarts the agent, reading the login shell again, and asks whether it's signed in: for after
    /// the user signed in some other way (over SSH, say).
    func checkAgentSignIn(_ agentID: String) async throws -> HostAgent {
        guard let link = agents[agentID] else { throw HostError.unknownAgent(agentID) }
        try requireIdle(link, to: "Check again")
        try syncAgents(agentOrder.compactMap { agents[$0]?.spec }, refreshEnvironment: true)
        try await restart(link)
        await awaitFreshStatus(of: link)
        return link.hostAgent
    }

    // MARK: - Keys

    /// Saves a key for one of the agent's methods and signs in with it: an `apiKey` method takes it
    /// in `authenticate`; an `environment` one starts the agent again with its variable set.
    func setAgentCredential(_ params: SetAgentCredentialParams, by client: ClientLink) async throws -> HostAgent {
        guard client.grants.manageHost else { throw HostError.notAuthorized("save sign-in keys") }
        guard agents[params.agentID] != nil else { throw HostError.unknownAgent(params.agentID) }
        let secret = params.secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !secret.isEmpty, secret.utf8.count <= 16_384, !secret.contains(where: { $0.isNewline || $0 == "\0" })
        else {
            throw RPCError(code: -32602, message: "That key is empty or isn't one line of text.")
        }
        let link = try await readyAgent(params.agentID)
        guard let method = link.authMethods.first(where: { $0.id == params.methodID }), method.takesSecret else {
            throw RPCError(
                code: -32602, message: "\(link.spec.name) has no sign-in method \(params.methodID) that takes a key.")
        }
        let credential = HostCredential(
            agentID: params.agentID, methodID: method.id, variable: method.secretVariable?.name, secret: secret)
        if credential.variable == nil {
            do {
                try await authenticate(link, methodID: method.id, apiKey: secret)
            } catch let error as RPCError {
                // The agent's answer goes back to the client verbatim, but never with the key in it.
                let data = error.data.flatMap {
                    (try? JSONEncoder().encode($0)).map { String(decoding: $0, as: UTF8.self) }
                }
                throw RPCError(
                    code: error.code, message: error.message.replacingOccurrences(of: secret, with: "<key>"),
                    data: data?.contains(secret) == true ? nil : error.data)
            }
            try save(credential, for: link)
        } else {
            try requireIdle(link, to: "Save the key")
            try save(credential, for: link)
            try await restart(link)
            // ACP's own env-var methods also want `authenticate` once the variable is set.
            if link.signIn.advertised.contains(where: { $0.id == method.id }) {
                try await authenticate(link, methodID: method.id)
            }
            await awaitFreshStatus(of: link)
        }
        logger.info("Saved a key for \(link.spec.id) (\(method.id))")
        return link.hostAgent
    }

    /// Forgets a saved key and stops the agent using it: one in a variable by restarting the agent
    /// without it; one the agent took in `authenticate` (and keeps itself, as Codex does) by signing
    /// it out, when it says that's what it's signed in with.
    func removeAgentCredential(_ params: AgentCredentialParams, by client: ClientLink) async throws -> HostAgent {
        guard client.grants.manageHost else { throw HostError.notAuthorized("remove sign-in keys") }
        guard let link = agents[params.agentID] else { throw HostError.unknownAgent(params.agentID) }
        guard
            let saved = try configuration.credentials.saved(for: params.agentID).first(where: {
                $0.methodID == params.methodID
            })
        else {
            refreshSavedCredentials(of: link)
            return link.hostAgent
        }
        if saved.variable != nil {
            try requireIdle(link, to: "Remove the key")
            try configuration.credentials.remove(agentID: params.agentID, methodID: params.methodID)
            refreshSavedCredentials(of: link)
            if link.peer != nil {
                try await restart(link)
                await awaitFreshStatus(of: link)
            }
        } else {
            try configuration.credentials.remove(agentID: params.agentID, methodID: params.methodID)
            refreshSavedCredentials(of: link)
            _ = try await readyAgent(params.agentID)
            await awaitFreshStatus(of: link)
            if let peer = link.peer, link.signIn.status?.kind == .apiKey,
                AgentAuthCapabilities(initializeResult: link.initializeResult).logout
            {
                _ = try await peer.request(LogoutRequest.method, LogoutRequest(), as: JSONValue.self)
            }
        }
        logger.info("Removed the key for \(link.spec.id) (\(params.methodID))")
        return link.hostAgent
    }

    /// The login-shell environment with the agent's saved keys in their variables. The plugin's own
    /// `env` still wins a clash (`AgentLaunch.command`).
    func launchEnvironment(of agentID: String) async -> [String: String] {
        var environment = await agentEnvironment()
        do {
            for credential in try configuration.credentials.saved(for: agentID) {
                if let variable = credential.variable {
                    environment[variable] = credential.secret
                }
            }
        } catch {
            logger.error("Couldn't read the keys saved for \(agentID): \(error.localizedDescription)")
        }
        if let spec = agents[agentID]?.spec {
            environment = tasks.prepareSkill(for: spec, environment: environment)
        }
        return environment
    }

    func refreshSavedCredentials(of link: AgentLink) {
        do {
            link.signIn.savedCredentials = try configuration.credentials.saved(for: link.spec.id).map(\.methodID)
                .sorted()
        } catch {
            logger.error("Couldn't read the keys saved for \(link.spec.id): \(error.localizedDescription)")
        }
    }

    private func save(_ credential: HostCredential, for link: AgentLink) throws {
        try configuration.credentials.save(credential)
        refreshSavedCredentials(of: link)
    }

    // MARK: - From the agent

    /// Notifications about signing in: who the agent is signed in as, and a link it's done with.
    static let signInNotifications: Set<String> = [AuthStatusNotification.method, "elicitation/complete"]

    func receiveSignInNotification(_ message: JSONRPCPeer.Message, from link: AgentLink) {
        if message.method == AuthStatusNotification.method {
            guard let status = try? message.params(as: AuthStatusNotification.self).authStatus else { return }
            link.signIn.status = status
            link.signIn.statusGeneration = link.generation
            // Signed in some other way, or by a key: requests will work again. Signed out is only
            // news when someone asked (`awaitFreshStatus`) or a request is turned away.
            if status.isSignedIn { link.needsSignIn = false }
        } else if let completed = try? message.params(as: RawElicitationComplete.self),
            completed.elicitationId == link.signIn.link?.elicitationID
        {
            endSignInLink(of: link, answer: .accept(content: [:]))
        }
    }

    /// Whether `message` is an `elicitation/create` for a sign-in: a URL scoped to a request, not a
    /// session's question.
    static func isSignInLink(_ message: JSONRPCPeer.Message) -> Bool {
        guard message.method == "elicitation/create", let request = try? message.params(as: RawSignInLinkRequest.self)
        else { return false }
        return request.mode == "url" && request.sessionId == nil
    }

    /// A page and code for the user, while `authenticate` runs. Anything else is cancelled so the
    /// agent isn't left waiting; so is a link that isn't a web page, since clients open it.
    func receiveSignInLink(_ message: JSONRPCPeer.Message, id: RequestID, from link: AgentLink) {
        guard let request = try? message.params(as: RawSignInLinkRequest.self),
            let url = request.url.flatMap(URL.init(string:)), url.scheme == "https" || url.scheme == "http",
            link.isSigningIn, link.signIn.link == nil
        else {
            try? link.peer?.respond(to: id, with: CreateElicitationResponse.cancel)
            return
        }
        link.signIn.link = PendingSignInLink(
            shown: HostSignInLink(url: url, message: request.message ?? ""), request: id,
            elicitationID: request.elicitationId)
    }

    private func endSignInLink(of link: AgentLink, answer: CreateElicitationResponse) {
        guard let pending = link.signIn.link else { return }
        link.signIn.link = nil
        try? link.peer?.respond(to: pending.request, with: answer)
    }

    // MARK: - Restarting

    /// Turns the request away, changing nothing, while one of the agent's sessions is working.
    private func requireIdle(_ link: AgentLink, to action: String) throws {
        let working = workingSessions(of: link)
        guard working > 0 else { return }
        let (tasks, finish, them) =
            working == 1 ? ("1 task", "it finishes", "it") : ("\(working) tasks", "they finish", "them")
        throw HostError.busy(
            "\(link.spec.name) is working on \(tasks) on \(configuration.machineName). \(action) when \(finish), or stop \(them)."
        )
    }

    private func workingSessions(of link: AgentLink) -> Int {
        sessions.values.filter { $0.record.agentID == link.spec.id && $0.isWorking }.count
    }

    /// Stops the agent if it runs and starts it again, failing if it doesn't start.
    private func restart(_ link: AgentLink) async throws {
        if link.peer != nil {
            let generation = link.generation
            link.end(cause: .agentRestarted)
            agentExited(link.spec.id, generation: generation)
        }
        _ = try await readyAgent(link.spec.id)
    }

    /// Waits a little for the status the agent sends after starting, when it sends one, and takes
    /// it as the answer to "is it signed in?".
    private func awaitFreshStatus(of link: AgentLink) async {
        guard AgentAuthCapabilities(initializeResult: link.initializeResult).reportsStatus else { return }
        let generation = link.generation
        let deadline = ContinuousClock.now + .seconds(10)
        while link.signIn.statusGeneration != generation, link.generation == generation, ContinuousClock.now < deadline
        {
            try? await Task.sleep(for: .milliseconds(100))
        }
        if link.signIn.statusGeneration == generation, let status = link.signIn.status {
            link.needsSignIn = !status.isSignedIn
        }
    }
}

extension AgentLink {
    /// Its methods: what it advertised last, then its plugin's (`AgentSignInState.authMethods`).
    var authMethods: [AuthMethod] {
        signIn.authMethods(declared: spec.authMethods)
    }
}

private struct RawSignInLinkRequest: Decodable {
    var mode: String
    var sessionId: String?
    var url: String?
    var message: String?
    var elicitationId: String?
}

private struct RawElicitationComplete: Decodable {
    var elicitationId: String
}
