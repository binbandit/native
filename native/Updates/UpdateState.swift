import Foundation

/// A release the updater found, as the user sees it before installing.
struct UpdateRelease: Equatable, Sendable {
    /// The version people read, such as "1.4.0" (`CFBundleShortVersionString`).
    let version: String
    /// The build number Sparkle compares (`CFBundleVersion`).
    let build: String
    /// Release notes drafted from conventional commits, in Markdown.
    var notes: String?
    let date: Date?
    /// Downloaded size in bytes, when the feed says.
    let size: UInt64?
    /// Sparkle marks an update critical when the feed says versions below it must update.
    let isCritical: Bool
    /// The Sparkle channel the release was published to; nil for stable releases.
    let channel: String?
}

/// Where the updater is. Every case has its own design (docs/releasing.md, "Every state").
enum UpdateState: Equatable {
    /// Waiting for the next scheduled check.
    case idle
    case checking
    case upToDate(checkedAt: Date)
    /// Found, not downloaded yet: automatic downloads are off, or the user asked to check.
    case available(UpdateRelease)
    /// `progress` is nil until the download's size is known.
    case downloading(UpdateRelease, progress: Double?)
    /// Unpacking and verifying the download.
    case preparing(UpdateRelease, progress: Double)
    /// Downloaded and verified. It installs at the next quit, or now with "Restart to Update".
    case ready(UpdateRelease)
    case installing(UpdateRelease)
    case failed(UpdateFailure)
    /// This build can't update itself.
    case unavailable(UpdateUnavailableReason)

    var release: UpdateRelease? {
        switch self {
        case .available(let release), .downloading(let release, _), .preparing(let release, _), .ready(let release),
            .installing(let release):
            release
        case .idle, .checking, .upToDate, .failed, .unavailable:
            nil
        }
    }

    /// True while Sparkle is busy and another check would only interrupt it.
    var isBusy: Bool {
        switch self {
        case .checking, .downloading, .preparing, .installing: true
        case .idle, .upToDate, .available, .ready, .failed, .unavailable: false
        }
    }
}

enum UpdateUnavailableReason: Equatable, Sendable {
    /// Debug builds would replace themselves with a release.
    case developmentBuild
    /// The feed or signing key is still a placeholder (docs/releasing.md, "One-time setup").
    case notConfigured
    /// iPad builds have no updater; the App Store or TestFlight updates them.
    case unsupportedPlatform
    /// The organization turned updates off (`policy.updates.enabled`).
    case managedByOrganization
    /// Sparkle refused to start, with its reason.
    case updaterFailed(String)
}

/// A failed check, download or install, worded the way `ErrorState` wants: what happened, what
/// Native already did, and what the user can do.
struct UpdateFailure: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case offline
        case feed
        case download
        case security
        case install
        case location
        case other
    }

    let kind: Kind
    let title: String
    let recovery: String
    let suggestion: String
    /// The underlying error, behind "Show Details".
    let details: String?
    /// Whether trying again could help; otherwise the suggestion points to GitHub.
    var canRetry: Bool { kind != .security && kind != .location }
}
