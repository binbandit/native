import Foundation
import NativeHostClient
import NativeHostProtocol
import Observation

/// The app's side of keeping awake: the user's policy (kept under `keepAwake.policy`), the app's
/// activity, and the engine that acts on both: the background host once Native runs its agents
/// there (`useHost`), else the app itself. Views and menu commands change the policy only through
/// these methods. On iPad there's no engine: it's a client, and never holds power assertions.
@Observable
final class KeepAwakeController {
    private(set) var policy: KeepAwakePolicy {
        didSet {
            defaults.set(try? JSONEncoder().encode(policy), forKey: Self.policyKey)
            apply()
        }
    }

    private(set) var status = KeepAwakeStatus.off
    /// The background host keeps the Mac awake, so the policy holds while Native is closed too.
    private(set) var isHostBacked = false
    /// Reassigned on every change to what it's read from (every streamed chunk, while agents work),
    /// so only a different value reaches the engine, which asks the power source each time.
    private(set) var activity = KeepAwakeActivity() {
        didSet {
            if activity != oldValue { apply() }
        }
    }

    /// Choices for "Stay awake for": 30 minutes to 8 hours.
    static let timerDurations: [Duration] = [
        .seconds(30 * 60), .seconds(3600), .seconds(2 * 3600), .seconds(4 * 3600), .seconds(8 * 3600),
    ]

    /// Nil when the app keeps nothing awake itself (iPad) and no host has taken over.
    @ObservationIgnored private var engine: (any KeepAwakeEngine)?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var following: Task<Void, Never>?
    private static let policyKey = "keepAwake.policy"
    /// Off until it's verified in the running app: `-NativeHostKeepAwake YES` hands keeping awake to
    /// the host. Off, the app keeps holding the assertions itself, as before.
    static let handsOverToHostByDefault = false

    static var handsOverToHost: Bool {
        // `bool(forKey:)` also reads a launch argument, which arrives as text ("YES").
        UserDefaults.standard.object(forKey: "NativeHostKeepAwake") == nil
            ? handsOverToHostByDefault : UserDefaults.standard.bool(forKey: "NativeHostKeepAwake")
    }

    /// Whether the app keeps its machine awake: on the Mac. An iPad's agents run on a host, so its
    /// keep-awake menu, status item and settings page are left out; a paired host's Keep Awake is
    /// set in that host's settings.
    static var isSupported: Bool {
        #if os(macOS)
        return true
        #else
        return false
        #endif
    }

    /// Quitting needs nothing: the system drops a process's power assertions when it exits.
    init(engine: (any KeepAwakeEngine)? = KeepAwakeController.inAppEngine(), defaults: UserDefaults = .standard) {
        self.defaults = defaults
        policy =
            defaults.data(forKey: Self.policyKey).flatMap { try? JSONDecoder().decode(KeepAwakePolicy.self, from: $0) }
            ?? KeepAwakePolicy()
        if let engine {
            connect(engine)
        }
    }

    /// The engine that holds power assertions in the app itself, where there is one.
    static func inAppEngine() -> (any KeepAwakeEngine)? {
        #if os(macOS)
        return KeepAwake()
        #else
        return nil
        #endif
    }

    /// Hands keeping awake to the host that runs this Mac's agents: it holds the assertions while
    /// they work, also after Native quits, and the policy goes to it. The app lets go of its own.
    func useHost(_ client: NativeHostClient) {
        guard Self.handsOverToHost else { return }
        engine?.stop()
        isHostBacked = true
        connect(KeepAwakeHostEngine(client: client))
    }

    private func connect(_ engine: any KeepAwakeEngine) {
        self.engine = engine
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
    ///
    /// `Observations` reads again once per change. A `withObservationTracking` re-armed from its
    /// own `onChange` can hear about one change twice, when reading updates other observable state
    /// during it (the sidebar's cached session lists do), and every extra re-arm doubled the
    /// observers: gigabytes and a busy core after opening a couple of dozen tasks.
    func follow(_ read: @escaping @MainActor @Sendable () -> KeepAwakeActivity) {
        following?.cancel()
        following = Task { [weak self] in
            for await activity in Observations(read) {
                guard let self else { return }
                if activity != self.activity {
                    self.activity = activity
                }
            }
        }
    }

    private func apply() {
        status = engine?.apply(policy, activity: activity) ?? .off
    }

    private func engineChanged(_ status: KeepAwakeStatus) {
        self.status = status
        // A timer that ran out goes away, so the menus stop offering to cancel it.
        if let until = policy.awakeUntil, until <= .now {
            policy.awakeUntil = nil
        }
    }
}
