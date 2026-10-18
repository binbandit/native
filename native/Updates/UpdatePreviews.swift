#if DEBUG
import Foundation

/// Sample states for previews and screenshots. A Debug build started with
/// `-updatePreviewState <name>` shows that state instead of starting Sparkle.
extension UpdateController {
    static func preview(_ name: String) -> UpdateController {
        let controller = UpdateController(current: .preview)
        controller.applyPreview(name)
        return controller
    }

    /// Returns false when `name` isn't a sample, so the caller starts Sparkle as usual.
    @discardableResult
    func applyPreview(_ name: String) -> Bool {
        let release = UpdateRelease(
            version: "1.4.0", build: "1240",
            notes: """
                ## New
                - **composer:** queue follow-ups while a turn runs
                - **sidebar:** drag tasks between projects
                ## Fixes
                - **transcript:** long diffs no longer stutter while scrolling
                - `gh` sign-in errors now say which account expired
                """,
            date: Date(timeIntervalSinceNow: -86_400), size: 48_200_000, isCritical: false, channel: nil)
        let samples: [String: UpdateState] = [
            "idle": .idle,
            "checking": .checking,
            "upToDate": .upToDate(checkedAt: .now),
            "available": .available(release),
            "downloading": .downloading(release, progress: 0.42),
            "preparing": .preparing(release, progress: 0.8),
            "ready": .ready(release),
            "readyWaiting": .ready(release),
            "installing": .installing(release),
            "failedOffline": .failed(
                UpdateFailure(
                    kind: .offline, title: "Native couldn't reach GitHub",
                    recovery: "Native is still on version \(current.version). It checks again on its own.",
                    suggestion: "Check your internet connection, then try again.",
                    details: "The Internet connection appears to be offline. (NSURLErrorDomain -1009)")),
            "failedSecurity": .failed(
                UpdateFailure(
                    kind: .security, title: "The update failed a security check",
                    recovery:
                        "Native is still on version \(current.version). Native didn't install the download because it couldn't verify who made it.",
                    suggestion: "Download the latest release from GitHub instead.",
                    details: "EdDSA signature does not match. (SUSparkleErrorDomain 3001)")),
            "developmentBuild": .unavailable(.developmentBuild),
            "notConfigured": .unavailable(.notConfigured),
        ]
        guard let state = samples[name] else { return false }
        driverDidChange(state)
        if name == "readyWaiting" {
            previewPendingRestart(.whenTasksFinish)
        }
        restartContext = { UpdateRestartContext(workingTasks: 2, keepsRunning: name != "readyWaiting") }
        return true
    }
}

extension AppVersion {
    static let preview = AppVersion(
        info: [
            "CFBundleShortVersionString": "1.3.2", "CFBundleVersion": "1198",
            "SUFeedURL": "https://example.com/appcast.xml", "SUPublicEDKey": "preview",
            "NativeGitHubRepository": "native/native",
        ],
        channel: .current)
}
#endif
