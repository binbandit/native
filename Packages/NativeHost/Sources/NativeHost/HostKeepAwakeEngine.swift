import Foundation
import NativeHostProtocol

/// What holds power assertions on the host's machine: IOKit on a Mac (`NativeHostMac`), a fake in
/// tests. A host without one can't keep its machine awake, and says so.
public protocol HostPowerBackend: AnyObject, Sendable {
    /// Holds exactly `kinds`, named `name` (`pmset -g assertions` lists it), and returns what's
    /// held, which falls short when the system refused one.
    @discardableResult
    func hold(_ kinds: Set<PowerAssertionKind>, name: String) -> Set<PowerAssertionKind>
    /// The power source right now, for the battery rules.
    func powerState() -> PowerState
    /// Calls `onChange` whenever the power source or the battery's charge changes, from now on.
    func observePowerChanges(_ onChange: @escaping @Sendable () -> Void)
}

/// Keeps the host's machine awake as the user's policy says: while sessions work, always, or for a
/// while. It lives in the host because the host is what agents keep busy, with or without a window
/// open, so a droid doesn't sleep mid-task.
@HostActor
final class HostKeepAwakeEngine {
    private(set) var policy: KeepAwakePolicy
    private(set) var status = KeepAwakeStatus.off
    private(set) var held: Set<PowerAssertionKind> = []
    /// Called when the state changed: the policy, what it calls for, or what's held.
    var onChange: ((HostKeepAwakeState) -> Void)?

    private var workingAgents = 0
    private let backend: (any HostPowerBackend)?
    private let now: @Sendable () -> Date
    private var timerEnd: Task<Void, Never>?
    private var isStarted = false

    init(backend: (any HostPowerBackend)?, policy: KeepAwakePolicy, now: @escaping @Sendable () -> Date = { .now }) {
        self.backend = backend
        self.policy = policy
        self.now = now
    }

    var state: HostKeepAwakeState {
        HostKeepAwakeState(policy: policy, status: status, held: held, isSupported: backend != nil)
    }

    /// Applies the policy for the sessions working now, and follows the power source from then on.
    func start(workingAgents: Int) {
        guard !isStarted else { return }
        isStarted = true
        self.workingAgents = workingAgents
        backend?.observePowerChanges { [weak self] in
            Task { @HostActor in self?.evaluate() }
        }
        scheduleTimerEnd()
        evaluate()
    }

    func setPolicy(_ policy: KeepAwakePolicy) {
        guard policy != self.policy else { return }
        self.policy = policy
        scheduleTimerEnd()
        evaluate(forceNotify: true)
    }

    /// Sessions with work under way. Only a different count reaches the backend, which reads the
    /// power source each time.
    func setWorkingAgents(_ count: Int) {
        guard count != workingAgents else { return }
        workingAgents = count
        guard isStarted else { return }
        evaluate()
    }

    private func evaluate(forceNotify: Bool = false) {
        let power = backend?.powerState() ?? PowerState()
        let next = KeepAwakeStatus.evaluate(policy, workingAgents: workingAgents, power: power, now: now())
        let nextHeld = backend?.hold(next.assertions, name: Self.assertionName(for: next.reason)) ?? []
        let changed = next != status || nextHeld != held
        status = next
        held = nextHeld
        if changed || forceNotify {
            onChange?(state)
        }
    }

    private func scheduleTimerEnd() {
        timerEnd?.cancel()
        guard let until = policy.timer(at: now()) else { return }
        let wait = until.timeIntervalSince(now())
        timerEnd = Task { [weak self] in
            // ContinuousClock keeps counting while the machine sleeps, so a timer that ran out
            // during sleep ends right after waking.
            try? await Task.sleep(for: .seconds(wait), clock: .continuous)
            guard !Task.isCancelled else { return }
            self?.evaluate()
        }
    }

    /// What `pmset -g assertions` and Activity Monitor show as the reason.
    private static func assertionName(for reason: KeepAwakeStatus.Reason) -> String {
        switch reason {
        case .agentsWorking: "Native is keeping this machine awake while agents work"
        case .timer: "Native is keeping this machine awake for a set time"
        default: "Native is keeping this machine awake"
        }
    }
}
