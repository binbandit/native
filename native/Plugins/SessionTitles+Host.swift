import ACP
import AIInstructions
import Foundation
import NativeHostClient
import NativeHostProtocol
import SessionTitling
import os

/// Where a task in a host lives, for sending its titles there.
struct HostTitleLink {
    let client: NativeHostClient
    let session: HostSessionID
    let folder: URL
}

// Titles of tasks in a host (docs/durability.md, "Titles"; `HostTitlesWiring` says which hosts). The
// host writes them from each task's first message and keeps the user's renames, so a task started
// with the app closed or asleep still gets its title. This side mirrors them into the titles every
// view reads (and keeps them for tasks the host later closes), sends renames back, and writes a
// title when the host asks for one.
extension SessionTitles {
    private static let hostLogger = Logger(subsystem: "Native", category: "Titles")

    /// Follows the titles of `client`'s tasks from now on, once the host has heard who writes them.
    /// `titler` is the one plugins provide now; `landed` hears each task's title as it arrives, so
    /// its workspace (a provisional branch) can be named after it. `isCurrent` turns false when the
    /// client stops for good (a paired host's pairing was replaced or removed), and following it
    /// stops with it. A host that can't keep titles (an older build) or won't take this app's
    /// configuration is left alone, and its tasks are titled here as before.
    func follow(
        _ client: NativeHostClient, titler: @escaping () -> (any SessionTitler)?,
        while isCurrent: @escaping @MainActor @Sendable () -> Bool = { true },
        landed: @escaping (Key, URL, String) -> Void
    ) async {
        hostTitler = titler
        titleLanded = landed
        guard await configure(client) else { return }
        await client.addEventHandler { [weak self] event in
            await self?.receive(event, from: client, while: isCurrent)
        }
        keepConfigured(client, while: isCurrent)
        await adoptAll(from: client)
    }

    /// For this Mac's host with `HostTitles` off: this app writes titles, so the host is told not
    /// to, now and whenever it comes back.
    func leaveTitlesToApp(on client: NativeHostClient) async {
        let off = ConfigureTitlesParams(provider: .off)
        try? await client.configureTitles(off)
        await client.addEventHandler { event in
            guard case .connection(.connected) = event else { return }
            Task { try? await client.configureTitles(off) }
        }
    }

    /// Whether a host titles the task, so the app doesn't too.
    func isTitledByHost(_ key: Key) -> Bool {
        hostLinks[key] != nil
    }

    /// Sends the user's title for `key` to the host the task is in, if it's in one.
    func sendRename(_ key: Key) {
        guard let link = hostLinks[key] else { return }
        unsyncedRenames.insert(key)
        renamesInFlight[key, default: 0] += 1
        let params = SetSessionTitleParams(sessionID: link.session, title: userTitle(for: key), source: .user)
        Task {
            var sent = false
            do {
                try await link.client.setSessionTitle(params)
                sent = true
            } catch {
                Self.hostLogger.error("Couldn't send a rename to the host: \(error.localizedDescription)")
            }
            let remaining = renamesInFlight[key, default: 1] - 1
            renamesInFlight[key] = remaining > 0 ? remaining : nil
            guard remaining == 0 else { return }
            if sent {
                unsyncedRenames.remove(key)
            } else if let current = hostLinks[key], current.client !== link.client {
                // The task's host was paired again meanwhile: the new pairing takes the rename now.
                // Otherwise it goes when the host is back.
                sendRename(key)
            }
        }
    }

    // MARK: - From the host

    private func receive(
        _ event: NativeHostClient.Event, from client: NativeHostClient, while isCurrent: @MainActor () -> Bool
    ) {
        // A replaced pairing's client may still hand over what it read before it stopped.
        guard isCurrent() else { return }
        switch event {
        case .sessionChanged(let summary):
            adopt(summary, from: client)
        case .sessionClosed(let id):
            // Its titles stay here; a rename now stays here too, until the host opens it again.
            hostLinks = hostLinks.filter { $0.value.session != id }
        case .connection(.connected):
            // A restarted host hears the configuration again, and what changed meanwhile comes in.
            Task {
                guard await configure(client) else { return }
                await adoptAll(from: client)
            }
        default:
            break
        }
    }

    private func adoptAll(from client: NativeHostClient) async {
        guard let summaries = try? await client.sessions() else { return }
        for summary in summaries {
            adopt(summary, from: client)
        }
    }

    /// Takes in what the host says about a task's titles. The host is the source of truth, except
    /// for a rename of this app's it hasn't confirmed, and titles it never had: ones written here
    /// before titles moved to the host, or before the host reopened the task.
    private func adopt(_ summary: HostSessionSummary, from client: NativeHostClient) {
        guard summary.origin != .announced, let agentSessionID = summary.agentSessionID else { return }
        let key = Key(agent: AgentDefinition.ID(rawValue: summary.agentID), session: agentSessionID)
        let link = HostTitleLink(
            client: client, session: summary.id, folder: URL(filePath: summary.cwd, directoryHint: .isDirectory))
        hostLinks[key] = link
        let titles = summary.titles ?? HostSessionTitles()
        let before = namedTitle(for: key)
        if renamesInFlight[key] == nil {
            if unsyncedRenames.contains(key) || (titles.user == nil && userTitle(for: key) != nil) {
                sendRename(key)
            } else {
                setUserTitle(titles.user, for: key)
            }
        }
        if let generated = titles.generated {
            setGeneratedTitle(generated, for: key)
        } else if let known = generatedTitle(for: key), titles.request == nil, writtenForHosts.insert(key).inserted {
            send(SetSessionTitleParams(sessionID: link.session, title: known, source: .generated), on: link)
        }
        setFallbackTitle(titles.fallback, for: key)
        if let request = titles.request {
            writeTitle(request, for: key, on: link)
        }
        guard let after = namedTitle(for: key) else { return }
        if after != before || landedTitles.insert(key).inserted {
            titleLanded(key, link.folder, after)
        }
    }

    /// Writes the title the host asked for, with this app's titler and the user's instructions for
    /// the task's folder. Repeated summaries don't retry it; the host requests one retry on the
    /// next turn with a new attempt number. A title that never reached the host (it restarted, or
    /// the pairing was replaced while it was on its way) is written again when the host next asks,
    /// or right away through the task's new pairing.
    private func writeTitle(_ request: HostTitleRequest, for key: Key, on link: HostTitleLink) {
        guard userTitle(for: key) == nil, generatedTitle(for: key) == nil,
            let titler = hostTitler(), requestsForHosts[key] != request
        else { return }
        requestsForHosts[key] = request
        let titleRequest = TitleRequest(
            projectName: request.projectName, prompt: request.prompt,
            instructions: AIInstructionsStore.shared.addition(for: .title, in: link.folder))
        Task {
            let title: String?
            do {
                title = try await titler.title(for: titleRequest)
            } catch {
                Self.hostLogger.error("Couldn't write a title the host asked for: \(error.localizedDescription)")
                return
            }
            guard let title else { return }
            do {
                try await link.client.setSessionTitle(
                    SetSessionTitleParams(sessionID: link.session, title: title, source: .generated))
            } catch {
                Self.hostLogger.error("Couldn't send a title to the host: \(error.localizedDescription)")
                // An answer from the host (an error) means it arrived; only a lost one goes again.
                guard !(error is RPCError), requestsForHosts[key] == request else { return }
                requestsForHosts[key] = nil
                if let current = hostLinks[key], current.client !== link.client {
                    writeTitle(request, for: key, on: current)
                }
            }
        }
    }

    private func send(_ params: SetSessionTitleParams, on link: HostTitleLink) {
        Task { try? await link.client.setSessionTitle(params) }
    }

    /// Tells the host who writes titles and with which of the user's instructions. False when the
    /// host can't keep titles.
    @discardableResult
    private func configure(_ client: NativeHostClient) async -> Bool {
        do {
            try await client.configureTitles(hostConfiguration())
            return true
        } catch {
            Self.hostLogger.error("The host can't keep titles: \(error.localizedDescription)")
            return false
        }
    }

    /// Configures the host again whenever the titler or the user's instructions change, until the
    /// client stops for good.
    private func keepConfigured(
        _ client: NativeHostClient, while isCurrent: @escaping @MainActor @Sendable () -> Bool
    ) {
        Task { [weak self] in
            let changes = Observations { [weak self] in self?.hostConfiguration() }
            for await _ in changes.dropFirst() {
                guard let self, isCurrent() else { return }
                await configure(client)
            }
        }
    }

    private func hostConfiguration() -> ConfigureTitlesParams {
        let instructions = SessionTitleInstructions(AIInstructionsStore.shared.settings)
        return ConfigureTitlesParams(
            provider: hostTitler().map { $0.hostProvider ?? .client } ?? .off,
            instructions: HostTitleInstructions(
                global: instructions.global, projects: instructions.projects, managed: instructions.managed))
    }
}
