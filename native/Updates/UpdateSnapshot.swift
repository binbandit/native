import Foundation

/// The updater's state as plain values, for the host to serve paired devices as this Mac's update
/// status (`_native/host/update/status`, docs/releasing.md "Remote updates"). The host's wiring maps
/// it onto the protocol's `HostUpdateStatus`.
struct UpdateSnapshot: Equatable, Sendable {
    enum Phase: String, Sendable {
        case idle, checking, upToDate, available, downloading, ready, installing, failed, unavailable
    }

    let phase: Phase
    let currentVersion: String
    let currentBuild: String
    let channel: UpdateChannel
    let available: UpdateRelease?
    /// 0...1 while downloading or preparing, when the size is known.
    let progress: Double?
    /// The failure or the reason updates are off, in the words the Mac shows.
    let message: String?
    let releaseNotesURL: URL?
    let lastChecked: Date?
    /// An install that's waiting: for the download, or for working tasks to finish.
    let pendingInstall: UpdateController.RestartTiming?
    let canInstall: Bool

    init(
        state: UpdateState, current: AppVersion, channel: UpdateChannel, lastChecked: Date?,
        pendingRestart: UpdateController.RestartTiming?, canInstall: Bool
    ) {
        currentVersion = current.version
        currentBuild = current.build
        self.channel = channel
        available = state.release
        self.lastChecked = lastChecked
        pendingInstall = pendingRestart
        self.canInstall = canInstall && state.release != nil
        releaseNotesURL = current.allReleasesURL
        switch state {
        case .idle: (phase, progress, message) = (.idle, nil, nil)
        case .checking: (phase, progress, message) = (.checking, nil, nil)
        case .upToDate: (phase, progress, message) = (.upToDate, nil, nil)
        case .available: (phase, progress, message) = (.available, nil, nil)
        case .downloading(_, let fraction): (phase, progress, message) = (.downloading, fraction, nil)
        case .preparing(_, let fraction): (phase, progress, message) = (.downloading, fraction, nil)
        case .ready: (phase, progress, message) = (.ready, nil, nil)
        case .installing: (phase, progress, message) = (.installing, nil, nil)
        case .failed(let failure):
            (phase, progress, message) = (.failed, nil, "\(failure.title). \(failure.suggestion)")
        case .unavailable(let reason): (phase, progress, message) = (.unavailable, nil, reason.summary)
        }
    }
}

extension UpdateUnavailableReason {
    /// One line for a remote client.
    var summary: String {
        switch self {
        case .developmentBuild: "Updates are off in development builds."
        case .notConfigured: "This build has no update feed or signing key."
        case .unsupportedPlatform: "This device updates through the App Store."
        case .updaterFailed(let message): "The updater didn't start: \(message)"
        }
    }
}
