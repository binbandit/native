import Foundation
import Observation

/// Native's updater as state SwiftUI can observe. On macOS Sparkle does the work
/// (`SparkleUpdateDriver`); builds without Sparkle, such as iPad, report `.unavailable` and every
/// action is a no-op. Views read `state` and call these methods, so they never touch Sparkle or
/// AppKit. See docs/releasing.md.
@Observable
final class UpdateController {
    /// When an update downloads after the user asked for it, what happens once it's ready.
    enum RestartTiming: Equatable {
        case now
        case whenTasksFinish
    }

    private(set) var state: UpdateState
    /// When Sparkle last looked for an update, scheduled or not.
    private(set) var lastChecked: Date?
    private(set) var channel: UpdateChannel
    private(set) var automaticallyChecks = true
    private(set) var automaticallyDownloads = true
    /// Set after the user asked to restart once their tasks finish; cleared when that happens.
    private(set) var pendingRestart: RestartTiming?

    let current: AppVersion
    /// The channels this build can switch between (one for Nightly).
    let channels: [UpdateChannel]

    /// What a restart would interrupt right now. The app wires this to its sessions.
    @ObservationIgnored var restartContext: () -> UpdateRestartContext = { .idle }

    @ObservationIgnored private var idleWatch: Task<Void, Never>?
    #if canImport(Sparkle)
    @ObservationIgnored private var driver: SparkleUpdateDriver?
    #endif

    init(current: AppVersion = .current, defaults: UserDefaults = .standard) {
        self.current = current
        channels = UpdateChannel.choices(for: current.channel)
        channel = UpdateChannel.preferred(for: current.channel, defaults: defaults)
        state = Self.unavailableReason(for: current).map(UpdateState.unavailable) ?? .idle
    }

    /// Starts Sparkle and its scheduled checks. Call once, at launch.
    func start() {
        #if DEBUG
        if let sample = UserDefaults.standard.string(forKey: "updatePreviewState"), applyPreview(sample) {
            return
        }
        #endif
        #if canImport(Sparkle)
        guard driver == nil, case .idle = state else { return }
        let driver = SparkleUpdateDriver(controller: self)
        do {
            try driver.start()
            self.driver = driver
            automaticallyChecks = driver.automaticallyChecks
            automaticallyDownloads = driver.automaticallyDownloads
            lastChecked = driver.lastChecked
        } catch {
            state = .unavailable(.updaterFailed(error.localizedDescription))
        }
        #endif
    }

    var isAvailable: Bool {
        if case .unavailable = state { false } else { true }
    }

    /// Whether the toolbar's update button has anything to show; the toolbar leaves the slot out
    /// otherwise.
    var showsToolbarButton: Bool {
        switch state {
        case .available, .downloading, .preparing, .ready, .installing: true
        case .idle, .checking, .upToDate, .failed, .unavailable: false
        }
    }

    // MARK: - Actions

    /// "Check for Updates…": looks now, even while a scheduled check is waiting.
    func checkForUpdates() {
        #if canImport(Sparkle)
        driver?.checkForUpdates()
        #endif
    }

    /// The one "Update" action: downloads the update if needed, then restarts into it.
    func installUpdate(_ timing: RestartTiming = .now) {
        #if canImport(Sparkle)
        guard let driver else { return }
        switch state {
        case .available:
            pendingRestart = timing
            driver.install()
        case .downloading, .preparing:
            pendingRestart = timing
        case .ready:
            restart(timing, driver: driver)
        case .idle, .checking, .upToDate, .installing, .failed, .unavailable:
            break
        }
        #endif
    }

    /// Keeps the update ready without restarting; it installs at the next quit.
    func cancelPendingRestart() {
        pendingRestart = nil
        idleWatch?.cancel()
        idleWatch = nil
    }

    /// Not now: the next scheduled check offers it again.
    func remindLater() {
        #if canImport(Sparkle)
        driver?.remindLater()
        #endif
    }

    /// Never offer this version again; a newer one still shows up.
    func skipVersion() {
        #if canImport(Sparkle)
        driver?.skip()
        #endif
    }

    func cancelDownload() {
        pendingRestart = nil
        #if canImport(Sparkle)
        driver?.cancelDownload()
        #endif
    }

    /// Clears a failure so the page shows when the next check will run.
    func dismissFailure() {
        if case .failed = state {
            state = .idle
        }
    }

    // MARK: - Preferences

    func setChannel(_ channel: UpdateChannel) {
        guard channels.contains(channel), channel != self.channel else { return }
        self.channel = channel
        UserDefaults.standard.set(channel.rawValue, forKey: UpdateChannel.storageKey)
        #if canImport(Sparkle)
        // An offer from the old channel no longer applies; look again on the new one.
        if case .available = state {
            driver?.remindLater()
        }
        driver?.recheckSoon()
        #endif
    }

    func setAutomaticallyChecks(_ isOn: Bool) {
        automaticallyChecks = isOn
        #if canImport(Sparkle)
        driver?.automaticallyChecks = isOn
        #endif
    }

    func setAutomaticallyDownloads(_ isOn: Bool) {
        automaticallyDownloads = isOn
        #if canImport(Sparkle)
        driver?.automaticallyDownloads = isOn
        #endif
    }

    // MARK: - Driver callbacks

    /// Sparkle moved to a new state.
    func driverDidChange(_ newState: UpdateState) {
        if case .upToDate(let date) = newState {
            lastChecked = date
        }
        if case .failed = newState {
            pendingRestart = nil
        }
        state = newState
        if case .ready = newState, let pendingRestart {
            #if canImport(Sparkle)
            if let driver {
                restart(pendingRestart, driver: driver)
            }
            #endif
        }
    }

    func driverDidCheck(at date: Date?) {
        lastChecked = date ?? lastChecked
    }

    /// The release notes arrived separately from the feed.
    func driverDidLoadNotes(_ notes: String) {
        guard var release = state.release else { return }
        release.notes = notes
        switch state {
        case .available: state = .available(release)
        case .downloading(_, let progress): state = .downloading(release, progress: progress)
        case .preparing(_, let progress): state = .preparing(release, progress: progress)
        case .ready: state = .ready(release)
        case .installing: state = .installing(release)
        case .idle, .checking, .upToDate, .failed, .unavailable: break
        }
    }

    #if DEBUG
    func previewPendingRestart(_ timing: RestartTiming?) {
        pendingRestart = timing
    }
    #endif

    // MARK: - Restarting

    #if canImport(Sparkle)
    private func restart(_ timing: RestartTiming, driver: SparkleUpdateDriver) {
        switch timing {
        case .now:
            cancelPendingRestart()
            driver.installAndRelaunch()
        case .whenTasksFinish:
            pendingRestart = .whenTasksFinish
            watchForIdle(driver: driver)
        }
    }

    /// Restarts once nothing is working. Polling is enough: it only runs while the user waits for
    /// their tasks, and a few seconds' delay is invisible next to a turn.
    private func watchForIdle(driver: SparkleUpdateDriver) {
        idleWatch?.cancel()
        idleWatch = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.restartContext().workingTasks == 0 {
                    self.restart(.now, driver: driver)
                    return
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
    #endif

    private static func unavailableReason(for version: AppVersion) -> UpdateUnavailableReason? {
        #if canImport(Sparkle)
        // A build run from source has no feed: a release would replace it.
        if version.channel == .dev { return .developmentBuild }
        return version.isUpdateConfigured ? nil : .notConfigured
        #else
        return .unsupportedPlatform
        #endif
    }
}
