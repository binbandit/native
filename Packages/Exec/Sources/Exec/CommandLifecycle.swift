#if os(macOS)
import Foundation
import Synchronization

/// One command's launch, timeout, stop and exit, serialized. Cancellation can arrive before the
/// process has launched, and `Process.terminate()` raises an Objective-C exception for a process that
/// never ran.
///
/// Stopping signals the command's process group rather than its pid: `Process` makes each command a
/// group leader, and a group's id can't be handed to a new process while anything in the group is
/// alive, so a signal can't reach an unrelated process that was given a recycled pid. It also reaches
/// what a script started, which would otherwise hold the output open after the script was killed.
final class CommandLifecycle: @unchecked Sendable {
    enum StopReason: Sendable {
        case cancelled
        case timedOut
    }

    private struct State {
        /// What `kill` signals once launched: the command's process group (a negative id), or the
        /// command alone if it somehow isn't a group leader.
        var target: pid_t?
        var hasExited = false
        var stopReason: StopReason?
        var timeout: Task<Void, Never>?
    }

    // `Process` isn't Sendable; every access goes through `state`'s lock.
    private let process: Process
    private let gracePeriod: Duration
    private let state = Mutex(State())

    /// `gracePeriod` is how long a stopped command, and everything it started, gets to exit before
    /// being killed.
    init(_ process: Process, gracePeriod: Duration) {
        self.process = process
        self.gracePeriod = gracePeriod
    }

    var stopReason: StopReason? { state.withLock { $0.stopReason } }

    /// Launches the process, unless it was cancelled first, and starts its timeout.
    func launch(timeout: Duration?) throws {
        try state.withLock { state in
            if state.stopReason == .cancelled { throw CancellationError() }
            try process.run()
            let pid = process.processIdentifier
            // getpgid fails only once the command has been reaped, and then its group is all that's left.
            let group = getpgid(pid)
            state.target = group == -1 || group == pid ? -pid : pid
            if let timeout {
                state.timeout = Task { [self] in
                    guard (try? await Task.sleep(for: timeout)) != nil else { return }
                    stop(.timedOut)
                }
            }
        }
    }

    /// Records that the command exited: stopping it does nothing from here on, and its timeout is
    /// moot.
    func exited() {
        state.withLock { state in
            state.hasExited = true
            state.timeout?.cancel()
            state.timeout = nil
        }
    }

    /// Records why the command stopped early and asks its process group to stop, then kills whatever
    /// is left of the group after the grace period: that includes processes that ignored the request
    /// and outlived the command itself, which would otherwise hold its output open. The first reason
    /// wins; stopping a command that already exited does nothing.
    func stop(_ reason: StopReason) {
        let target: pid_t? = state.withLock { state in
            guard state.stopReason == nil, !state.hasExited else { return nil }
            state.stopReason = reason
            state.timeout?.cancel()
            state.timeout = nil
            guard let target = state.target else { return nil }
            kill(target, SIGTERM)
            return target
        }
        guard let target else { return }
        let gracePeriod = gracePeriod
        Task {
            try? await Task.sleep(for: gracePeriod)
            kill(target, SIGKILL)
        }
    }
}
#endif
