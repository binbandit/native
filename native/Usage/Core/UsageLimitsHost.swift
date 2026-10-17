import Foundation

/// What `UsageLimits` needs from the app to act on sessions. `AppModel` conforms.
protocol UsageLimitsHost: AnyObject {
    /// The session, loaded from the agent if it isn't open yet; nil while that isn't possible
    /// (its agent is still starting, or the session is gone).
    func resumableSession(_ target: LimitTarget) async -> (any LimitResumable)?
    /// Brings the session forward, as when the user clicks a notification about it.
    func show(_ target: LimitTarget)
}
