import Foundation

/// Where this run of Native runs its agents (`docs/durability.md`, "Process model and lifecycle").
/// Decided once at launch: a session can't move between the app and a host while it runs.
enum HostPlacement: Equatable {
    /// Not decided yet; launch is still starting the host.
    case pending
    /// Inside the app, as before durable sessions: the user turned background agents off.
    case inApp
    /// In the background host, which keeps them working after Native quits.
    case background
    /// In a host Native started itself, which stops with the app, because the background one
    /// couldn't run.
    case attached(HostFallback)
    /// Inside the app, because no host came up at all.
    case inAppFallback(HostFallback)

    /// Whether agents keep working after the app quits.
    var outlivesApp: Bool {
        self == .background
    }

    /// Whether sessions go through a host this run.
    var usesHost: Bool {
        switch self {
        case .background, .attached: true
        case .pending, .inApp, .inAppFallback: false
        }
    }

    /// Why agents stop with the app although the setting asks for them to keep running.
    var fallback: HostFallback? {
        switch self {
        case .attached(let fallback), .inAppFallback(let fallback): fallback
        case .pending, .inApp, .background: nil
        }
    }
}

/// Why the background host couldn't run this time.
enum HostFallback: Equatable {
    /// Native is switched off under System Settings › General › Login Items & Extensions › Allow in
    /// the Background. Native respects that rather than detaching anyway.
    case backgroundNotAllowed
    /// macOS or launchd turned the registration down.
    case registrationFailed(String)
    /// The host was started but never answered.
    case didNotStart(String)

    /// Remembers which fallback the user already read about, so the notice shows once per kind.
    var noticeKey: String {
        switch self {
        case .backgroundNotAllowed: "backgroundNotAllowed"
        case .registrationFailed: "registrationFailed"
        case .didNotStart: "didNotStart"
        }
    }

    /// The technical reason, for the notice's footnote.
    var reason: String? {
        switch self {
        case .backgroundNotAllowed: nil
        case .registrationFailed(let reason), .didNotStart(let reason): reason
        }
    }
}
