import Foundation
import Observation

/// The app's side of keeping awake: the user's policy (kept under `keepAwake.policy`), the app's
/// activity, and the engine that acts on both. Views and menu commands change the policy only
/// through these methods.
@Observable
final class KeepAwakeController {
    private(set) var policy: KeepAwakePolicy {
        didSet {
            defaults.set(try? JSONEncoder().encode(policy), forKey: Self.policyKey)
            apply()
        }
    }

    private(set) var status = KeepAwakeStatus.off
    private(set) var activity = KeepAwakeActivity() {
        didSet { apply() }
    }

    /// Choices for "Stay awake for": 30 minutes to 8 hours.
    static let timerDurations: [Duration] = [.seconds(30 * 60), .seconds(3600), .seconds(2 * 3600), .seconds(4 * 3600), .seconds(8 * 3600)]

    @ObservationIgnored private let engine: any KeepAwakeEngine
    @ObservationIgnored private let defaults: UserDefaults
    private static let policyKey = "keepAwake.policy"

    /// Quitting needs nothing: the system drops a process's power assertions when it exits.
    init(engine: any KeepAwakeEngine = KeepAwake(), defaults: UserDefaults = .standard) {
        self.engine = engine
        self.defaults = defaults
        policy = defaults.data(forKey: Self.policyKey).flatMap { try? JSONDecoder().decode(KeepAwakePolicy.self, from: $0) } ?? KeepAwakePolicy()
        engine.onChange = { [weak self] status in
            self?.engineChanged(status)
        }
        apply()
    }

    // MARK: - Choices

    var mode: KeepAwakeMode {
        get { policy.mode }
        set { setMode(newValue) }
    }

    var keepsDisplayOn: Bool {
        get { policy.keepsDisplayOn }
        set { policy.keepsDisplayOn = newValue }
    }

    var battery: KeepAwakeBatteryRule {
        get { policy.battery }
        set { policy.battery = newValue }
    }

    /// The running timer's end, if any.
    var awakeUntil: Date? {
        policy.timer(at: .now)
    }

    /// Picking a mode ends a running timer: the user just said what they want now.
    func setMode(_ mode: KeepAwakeMode) {
        policy.mode = mode
        policy.awakeUntil = nil
    }

    /// Off, While Agents Work, On, and around (⌃⌘A).
    func cycleMode() {
        setMode(policy.mode.next)
    }

    func stayAwake(for duration: Duration) {
        policy.awakeUntil = .now.addingTimeInterval(TimeInterval(duration.components.seconds))
    }

    func cancelTimer() {
        policy.awakeUntil = nil
    }

    // MARK: - Activity

    /// Keeps the activity in step with `read`, which reads observable app state (such as how many
    /// tasks are working), for as long as the controller lives.
    func follow(_ read: @escaping @MainActor () -> KeepAwakeActivity) {
        activity = withObservationTracking(read) { [weak self] in
            Task { @MainActor in self?.follow(read) }
        }
    }

    private func apply() {
        status = engine.apply(policy, activity: activity)
    }

    private func engineChanged(_ status: KeepAwakeStatus) {
        self.status = status
        // A timer that ran out goes away, so the menus stop offering to cancel it.
        if let until = policy.awakeUntil, until <= .now {
            policy.awakeUntil = nil
        }
    }
}
