import Foundation
import NativeHostProtocol
import SessionTitling

/// The titles engine's state in the host: who writes titles, and which are being written now.
struct HostTitling {
    var configuration = ConfigureTitlesParams(provider: .off)
    var generating: Set<HostSessionID> = []
}

extension MetaKey {
    /// The last `ConfigureTitlesParams` a client sent, as JSON.
    static let titleConfiguration = "title_configuration"
}

extension SessionTitleState {
    /// As summaries carry it; nil when there's nothing to tell.
    var hostTitles: HostSessionTitles? {
        guard user != nil || generated != nil || progress != nil else { return nil }
        return HostSessionTitles(
            user: user, generated: generated, fallback: fallback,
            request: progress == .waitingForClient
                ? request.map { HostTitleRequest(projectName: $0.projectName, prompt: $0.prompt, retry: retryCount) }
                : nil)
    }
}

extension SessionTitleInstructions {
    init(_ wire: HostTitleInstructions) {
        self.init(global: wire.global, projects: wire.projects, managed: wire.managed)
    }
}

extension HostSession {
    /// What clients name the task: the user's title, the generated one, the agent's, then its first
    /// message.
    var displayTitle: String? {
        titleState.displayTitle(agentTitle: record.title)
    }
}

// Titles (docs/durability.md, "Titles"): the host names each task from its first message, whether
// or not a client is attached, keeps the user's renames, and finishes a title the previous run
// left half-written. Clients hear of every change in the session's summary.
extension HostCore {
    /// Restores the configuration and every session's titles, then writes the titles the previous
    /// run didn't finish. Called at start, before any client is served.
    func resumeTitles() {
        do {
            if let stored = try store.meta(MetaKey.titleConfiguration) {
                titling.configuration = try JSONDecoder().decode(ConfigureTitlesParams.self, from: Data(stored.utf8))
            }
            for (id, state) in try store.titles() {
                sessions[id]?.titleState = state
            }
        } catch {
            logger.error("Couldn't read titles: \(error.localizedDescription)")
        }
        for session in sessions.values {
            if session.titleState.progress == .generating { writeTitle(for: session) }
        }
    }

    /// Who writes titles from now on, and with which of the user's instructions. The host's owner
    /// decides, or a device allowed to manage it: the laptop paired to a Mac mini sets up its titles.
    func configureTitles(_ params: ConfigureTitlesParams, by client: ClientLink) throws {
        guard client.grants.isLocal || client.grants.manageHost else {
            throw HostError.notAuthorized("change how this host titles tasks")
        }
        guard params != titling.configuration else { return }
        try store.setMeta(MetaKey.titleConfiguration, String(decoding: try JSONEncoder().encode(params), as: UTF8.self))
        titling.configuration = params
        // Titles left to clients may be this host's to write now.
        for session in sessions.values {
            writeTitle(for: session)
        }
    }

    /// Starts the task's title when its first message goes out. Called as every turn starts, once
    /// the prompt is in the session's log.
    func titleAfterPrompt(_ session: HostSession, prompt: OutgoingPrompt, kind: UnfinishedTurn.Kind) {
        guard kind == .prompt, titling.configuration.provider != .off,
            session.record.origin != .announced, !session.record.isAdopted
        else { return }
        // API clients can supply ACP content without duplicating it in the transcript fields.
        let content = prompt.content ?? []
        let contentText = content.compactMap { block -> String? in
            if case .text(let text) = block { text } else { nil }
        }.joined(separator: "\n")
        let names =
            prompt.attachments.isEmpty
            ? content.compactMap { block -> String? in
                switch block {
                case .resourceLink(_, let name): name
                case .resource(let uri, _): URL(string: uri)?.lastPathComponent
                case .image: "Image attachment"
                default: nil
                }
            } : prompt.attachments.map(\.name)
        let request = SessionTitleRequest(
            firstMessage: prompt.text.isEmpty ? contentText : prompt.text, attachmentNames: names, in: session.folder)
        guard session.titleState.beginIfNeeded(request) else { return }
        saveTitles(of: session)
        writeTitle(for: session)
    }

    /// The user's own title, or one a client wrote because the summary asked for it.
    func setSessionTitle(_ params: SetSessionTitleParams) throws {
        let session = try session(params.sessionID)
        let changed =
            switch params.source {
            case .user: session.titleState.rename(to: params.title)
            case .generated:
                params.title.map { session.titleState.accept(generated: $0, distinctFrom: otherTitles(near: session)) }
                    ?? false
            case .unknown: false
            }
        guard changed else { return }
        try store.setTitles(session.titleState, for: session.id)
        publish(session)
    }

    /// Writes a title the session still wants with this host's generator, or leaves it to clients
    /// when the host has none for the configured provider.
    private func writeTitle(for session: HostSession) {
        let state = session.titleState
        guard titling.configuration.provider != .off, var request = state.request, state.generated == nil,
            state.progress == .generating || state.progress == .waitingForClient,
            !titling.generating.contains(session.id)
        else { return }
        guard titling.configuration.provider == .onDevice, let generator = configuration.titleGenerator else {
            return leaveTitleToClients(session)
        }
        titling.generating.insert(session.id)
        request.instructions = SessionTitleInstructions(titling.configuration.instructions).addition(in: session.folder)
        request.otherTitles = otherTitles(near: session)
        let id = session.id
        Task {
            let result: Result<String?, any Error>
            do {
                result = .success(try await generator.title(for: request))
            } catch {
                result = .failure(error)
            }
            titleWritten(result, for: id)
        }
    }

    private func titleWritten(_ result: Result<String?, any Error>, for id: HostSessionID) {
        titling.generating.remove(id)
        guard let session = sessions[id], session.titleState.generated == nil else { return }
        switch result {
        case .success(nil):
            // No model here right now (Apple Intelligence is off, say); a client may have one.
            return leaveTitleToClients(session)
        case .success(let title?):
            // An answer with nothing usable in it counts as a failure.
            if !session.titleState.accept(generated: title, distinctFrom: otherTitles(near: session)) {
                session.titleState.fail()
            }
        case .failure(let error):
            logger.error("Couldn't title a session: \(error.localizedDescription)")
            session.titleState.fail()
        }
        saveTitles(of: session)
        publish(session)
    }

    private func leaveTitleToClients(_ session: HostSession) {
        guard session.titleState.progress != .waitingForClient else { return }
        session.titleState.waitForClient()
        saveTitles(of: session)
        publish(session)
    }

    /// The titles of the other live tasks in `session`'s project, which its own is told apart from.
    private func otherTitles(near session: HostSession) -> [String] {
        let project = SessionTitleRules.projectKey(of: session.folder)
        return sessions.values.filter { other in
            other.id != session.id && other.record.origin != .announced
                && SessionTitleRules.projectKey(of: other.folder) == project
        }.compactMap(\.displayTitle)
    }

    private func saveTitles(of session: HostSession) {
        do {
            try store.setTitles(session.titleState, for: session.id)
        } catch {
            logger.error("Couldn't save a session's titles: \(error.localizedDescription)")
        }
    }
}

extension HostSession {
    /// The folder the task runs in, which says which project's instructions apply.
    fileprivate var folder: URL {
        URL(filePath: record.cwd, directoryHint: .isDirectory)
    }
}
