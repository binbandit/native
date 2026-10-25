#if os(macOS)
import Foundation
import NativeHostProtocol

/// Keeps the Mac awake from inside the app, for runs where agents work in it rather than in a host
/// (Settings ▸ Background off, or no host answered): takes and releases the power assertions,
/// follows the power source for the battery rules, and ends timers on time. With a host,
/// `KeepAwakeHostEngine` hands the policy to it instead, since assertions belong to the process the
/// agents keep busy. Both decide with `KeepAwakeStatus.evaluate`. Mac only: an iPad is a client,
/// and keeping a machine awake belongs to the host its agents run on.
final class KeepAwake {
    private(set) var status = KeepAwakeStatus.off
    /// Called when the status changes on its own: a timer ran out, or the power source changed.
    var onChange: ((KeepAwakeStatus) -> Void)?

    private var policy = KeepAwakePolicy()
    private var activity = KeepAwakeActivity()
    private let assertions = PowerAssertions()
    private var powerMonitor: PowerSourceMonitor?
    private var timerTask: Task<Void, Never>?

    init() {
        powerMonitor = PowerSourceMonitor { [weak self] in
            self?.reevaluate()
        }
    }

    isolated deinit {
        timerTask?.cancel()
    }

    /// Applies a policy for the current activity; call again whenever either changes.
    func apply(_ policy: KeepAwakePolicy, activity: KeepAwakeActivity) -> KeepAwakeStatus {
        self.policy = policy
        self.activity = activity
        scheduleTimerEnd()
        return evaluate()
    }

    /// Releases everything, for quitting or handing over to a host.
    func stop() {
        timerTask?.cancel()
        policy = KeepAwakePolicy()
        status = .off
        assertions.set([], name: "")
    }

    private func reevaluate() {
        let previous = status
        if evaluate() != previous {
            onChange?(status)
        }
    }

    @discardableResult
    private func evaluate() -> KeepAwakeStatus {
        status = KeepAwakeStatus.evaluate(
            policy, workingAgents: activity.workingAgents, power: .current(), now: .now)
        assertions.set(status.assertions, name: Self.assertionName(for: status.reason))
        return status
    }

    private func scheduleTimerEnd() {
        timerTask?.cancel()
        guard let until = policy.timer(at: .now) else { return }
        timerTask = Task { [weak self] in
            // ContinuousClock keeps counting while the Mac sleeps, so a timer that ran out during
            // sleep ends right after waking.
            try? await Task.sleep(for: .seconds(until.timeIntervalSinceNow), clock: .continuous)
            guard !Task.isCancelled else { return }
            self?.reevaluate()
        }
    }

    /// What `pmset -g assertions` and Activity Monitor show as the reason.
    private static func assertionName(for reason: KeepAwakeStatus.Reason) -> String {
        switch reason {
        case .agentsWorking: "Native: keeping this Mac awake while agents work"
        case .timer: "Native: keeping this Mac awake for a set time"
        default: "Native: keeping this Mac awake"
        }
    }
}
#endif
