import NativeHostProtocol

/// What keeps the machine awake: `KeepAwakeHostEngine` hands the policy to the background host,
/// which holds the assertions while agents work there; `KeepAwake` holds them in the app when
/// agents run in it.
protocol KeepAwakeEngine: AnyObject {
    /// Called when the status changes on its own: a timer ran out, the power source changed, or
    /// the host said so.
    var onChange: ((KeepAwakeStatus) -> Void)? { get set }
    /// Applies a policy for the current activity; called again whenever either changes.
    func apply(_ policy: KeepAwakePolicy, activity: KeepAwakeActivity) -> KeepAwakeStatus
    /// Releases what this engine holds itself.
    func stop()
}

extension KeepAwake: KeepAwakeEngine {}

/// What the app is doing that keeping awake depends on, when agents run in it.
nonisolated struct KeepAwakeActivity: Hashable, Sendable {
    /// Tasks with a turn in flight.
    var workingAgents = 0
}
