/// Whether the user has a Focus such as Do Not Disturb on, for sounds to stay quiet during it.
/// `SystemFocusStatus` asks the system; tests and previews use a fixed one.
protocol FocusStatusProviding: AnyObject {
    /// Whether Native may know the Focus status.
    var access: FocusAccess { get }
    /// True while a Focus is on; nil when that can't be known (no access).
    var isFocused: Bool? { get }
    /// Asks for access if it was never asked; does nothing otherwise, so it's safe to call each
    /// time a sound would play.
    func requestAccessIfNeeded() async
}

/// Whether Native may see the user's Focus status.
nonisolated enum FocusAccess: Hashable, Sendable {
    /// Not asked yet: asked the first time a sound would play, never at launch.
    case notDetermined
    case allowed
    /// The user said no; System Settings can change that.
    case denied
    /// This build can't ask (it isn't signed with the Focus Status capability).
    case unavailable
}
