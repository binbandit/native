import Foundation
import NativeHostClient
import Synchronization

/// Quitting (`docs/durability.md`, "Quit"): ⌘Q leaves the background host working; Quit Native and
/// Stop Agents, or quitting after background agents were turned off, stops it first.
extension DurableHost {
    /// Quit Native and Stop Agents: the next quit stops the host and its agents too.
    func stopAgentsOnQuit() {
        stopsAgentsOnQuit = true
    }

    /// The host to stop before quitting, if quitting should stop it: asked for, or background agents
    /// were turned off while this run had them on (the setting says agents stop when Native quits).
    var hostToStopOnQuit: NativeHostClient? {
        guard placement.usesHost, stopsAgentsOnQuit || (placement == .background && !HostSessions.isEnabled)
        else { return nil }
        return client
    }

    /// Asks the host to end running turns as stopped, stop its agents and exit, waiting at most
    /// `limit`: quitting never hangs on it, and a request that never answers is left behind.
    nonisolated static func stop(_ client: NativeHostClient, within limit: Duration) async {
        await withCheckedContinuation { continuation in
            let first = FirstFinisher(continuation)
            Task {
                try? await client.shutdownHost(stopAgents: true)
                first.finish()
            }
            Task {
                try? await Task.sleep(for: limit)
                first.finish()
            }
        }
    }
}

/// Resumes a continuation once, for whichever of several racing tasks finishes first.
private nonisolated final class FirstFinisher: Sendable {
    private let continuation: Mutex<CheckedContinuation<Void, Never>?>

    init(_ continuation: CheckedContinuation<Void, Never>) {
        self.continuation = Mutex(continuation)
    }

    func finish() {
        let waiting = continuation.withLock { continuation in
            defer { continuation = nil }
            return continuation
        }
        waiting?.resume()
    }
}
