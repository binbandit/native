/// What keeps the machine awake. `KeepAwake` holds this Mac's power assertions; a client of a
/// remote host (Native on iPad) would send the policy to the host instead, since the host is the
/// machine the agents keep busy.
protocol KeepAwakeEngine: AnyObject {
    /// Called when the status changes on its own: a timer ran out, or the power source changed.
    var onChange: ((KeepAwakeStatus) -> Void)? { get set }
    /// Applies a policy for the current activity; called again whenever either changes.
    func apply(_ policy: KeepAwakePolicy, activity: KeepAwakeActivity) -> KeepAwakeStatus
    /// Releases everything.
    func stop()
}

extension KeepAwake: KeepAwakeEngine {}
