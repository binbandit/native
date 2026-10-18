import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol

// What the phone can do on a host. Each returns why it didn't work (or nil), so the screen that
// asked can say so where it was asked, and keep what the person typed.
extension HostConnection {
    enum SendOutcome: Equatable {
        case delivered(PromptDelivery)
        case notSent(String)
    }

    private func connectedClient() throws -> NativeHostClient {
        guard phase.isConnected, let client = client_ else { throw CompanionActionError.notConnected(name) }
        return client
    }

    func send(_ text: String, to sessionID: HostSessionID, behavior: PromptBehavior) async -> SendOutcome {
        do {
            let delivery = try await connectedClient().prompt(
                PromptParams(sessionID: sessionID, text: text, behavior: behavior))
            return .delivered(delivery)
        } catch {
            return .notSent(error.localizedDescription)
        }
    }

    func respond(_ sessionID: HostSessionID, toolCallID: String, option: PermissionOption?) async -> String? {
        do {
            try await connectedClient().respondPermission(
                RespondPermissionParams(sessionID: sessionID, toolCallID: toolCallID, optionID: option?.optionId))
            let verb = option.map { $0.kind.isAllow ? "Allowed" : "Rejected" } ?? "Dismissed"
            recordAnswer("\(verb) from this iPhone", toolCallID: toolCallID)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func cancel(_ sessionID: HostSessionID) async -> String? {
        await perform { try await $0.cancel(sessionID) }
    }

    func removeQueued(_ itemID: UUID, in sessionID: HostSessionID) async -> String? {
        await perform { try await $0.removeQueued(QueueItemParams(sessionID: sessionID, itemID: itemID)) }
    }

    func sendQueuedNow(_ itemID: UUID, in sessionID: HostSessionID) async -> String? {
        await perform { try await $0.sendQueuedNow(QueueItemParams(sessionID: sessionID, itemID: itemID)) }
    }

    /// Starts a task on the host and sends its first message. The Mac shows it without taking focus.
    func startTask(agentID: String, cwd: String, prompt: String) async -> Result<HostSessionID, CompanionActionError> {
        do {
            let client = try connectedClient()
            let summary = try await client.newSession(NewSessionParams(agentID: agentID, cwd: cwd))
            attach(summary.id)
            _ = try await client.prompt(PromptParams(sessionID: summary.id, text: prompt, behavior: .queue))
            return .success(summary.id)
        } catch let error as CompanionActionError {
            return .failure(error)
        } catch {
            return .failure(.failed(error.localizedDescription))
        }
    }

    func checkForUpdate() async -> String? {
        await perform { _ = try await $0.checkForUpdate() }
    }

    func installUpdate(_ when: HostUpdateStatus.When) async -> String? {
        await perform { _ = try await $0.installUpdate(when) }
    }

    func setPlugin(_ pluginID: String, enabled: Bool) async -> String? {
        await perform { _ = try await $0.setPluginEnabled(pluginID, enabled) }
    }

    private func perform(_ action: (NativeHostClient) async throws -> Void) async -> String? {
        do {
            try await action(connectedClient())
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}

enum CompanionActionError: Error, LocalizedError, Equatable {
    case notConnected(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected(let name): "\(name) isn't connected right now, so nothing was sent."
        case .failed(let reason): reason
        }
    }
}

extension PermissionOption.Kind {
    var isAllow: Bool {
        self == .allowOnce || self == .allowAlways
    }
}
