import Foundation
import NativeHostProtocol
import Observation

/// A user-requested restart, kept separate from the connection's automatic recovery. Completing a
/// shutdown request is not success: a different host process must answer on the same client.
@MainActor
@Observable
public final class BackgroundHostRestartModel {
    public enum State: Equatable, Sendable {
        case idle
        case confirming
        case waiting
        case restarting
        case done(Date)
        case failed(String)

        public var isBusy: Bool {
            switch self {
            case .waiting, .restarting: true
            default: false
            }
        }
    }

    public private(set) var state: State
    private var confirmsWaitingRestart = false
    private var restartID = UUID()

    public var isConfirmationPresented: Bool {
        state == .confirming || (state == .waiting && confirmsWaitingRestart)
    }

    public init(state: State = .idle) {
        self.state = state
    }

    public func request() {
        guard state != .restarting else { return }
        if state == .waiting {
            confirmsWaitingRestart = true
        } else {
            state = .confirming
        }
    }

    public func cancel() {
        confirmsWaitingRestart = false
        guard state == .confirming else { return }
        state = .idle
    }

    /// Uses the same shutdown and recovery path as an update, without changing the host's channel.
    /// Waiting has no deadline until work finishes; reconnecting after shutdown is bounded.
    public func restart(
        using client: NativeHostClient, whenIdle: Bool, timeout: Duration = .seconds(30)
    ) async {
        confirmsWaitingRestart = false
        guard state != .restarting, !(state == .waiting && whenIdle) else { return }
        // Escalating a scheduled restart replaces its monitor. Its late reply must not overwrite
        // the immediate restart's progress or result.
        let id = UUID()
        restartID = id
        state = whenIdle ? .waiting : .restarting
        let before = await client.hostInfo
        guard restartID == id else { return }
        guard let before else {
            state = .failed("The background host isn't connected. Native keeps trying to reconnect.")
            return
        }
        do {
            try await requestRestart(client, whenIdle: whenIdle, timeout: timeout)
            guard restartID == id else { return }
            var deadline: ContinuousClock.Instant? = whenIdle ? nil : .now + timeout
            while !Task.isCancelled {
                let after = await client.hostInfo
                guard restartID == id else { return }
                if let after, after.epoch != before.epoch {
                    state = .done(.now)
                    return
                }
                if deadline == nil, after == nil {
                    state = .restarting
                    deadline = .now + timeout
                }
                if let deadline, ContinuousClock.now >= deadline {
                    throw RestartFailure(
                        "The background host hasn't reconnected after the restart. Native keeps trying.")
                }
                try await Task.sleep(for: .milliseconds(50))
            }
            throw CancellationError()
        } catch {
            guard restartID == id else { return }
            state = .failed(error.localizedDescription)
        }
    }

    private func requestRestart(_ client: NativeHostClient, whenIdle: Bool, timeout: Duration) async throws {
        // JSON-RPC requests aren't cancellable. A structured task group would wait forever for an
        // unresponsive host even after its timeout won. Leave that reply to the connection, as Quit
        // and Stop Agents does, while bounding how long the UI waits.
        let (replies, continuation) = AsyncThrowingStream<Void, any Error>.makeStream()
        let request = Task {
            do {
                try await client.shutdownHost(stopAgents: false, immediately: !whenIdle)
                continuation.yield(())
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        let timer = Task {
            do {
                try await Task.sleep(for: timeout)
                continuation.finish(throwing: RestartFailure("The background host didn't answer the restart request."))
            } catch {}
        }
        defer {
            request.cancel()
            timer.cancel()
            continuation.finish()
        }
        for try await _ in replies { return }
        throw CancellationError()
    }

}

private struct RestartFailure: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
