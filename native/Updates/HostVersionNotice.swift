import SwiftUI

/// How this app and its background host compare. After an update the host keeps running the old
/// binary until its tasks finish (docs/releasing.md, "Updating the host"); opening an older copy of
/// Native meets a newer host. Either way both sides say so instead of failing quietly.
enum HostVersionStatus: Equatable, Sendable {
    case matched
    /// The host is from an earlier Native. It restarts onto this version once nothing is running.
    case hostRestartPending(hostVersion: String, workingTasks: Int)
    /// The host is newer than this app, so this app should update.
    case appOutdated(hostVersion: String)

    /// Compares build numbers (`CFBundleVersion`, the same for the app and its embedded host).
    /// `workingTasks` is what the host is running now.
    static func compare(appBuild: String, hostBuild: String, hostVersion: String, workingTasks: Int) -> Self {
        guard appBuild != hostBuild else { return .matched }
        if let app = Int(appBuild), let host = Int(hostBuild), host > app {
            return .appOutdated(hostVersion: hostVersion)
        }
        return .hostRestartPending(hostVersion: hostVersion, workingTasks: workingTasks)
    }
}

/// The banner for a mismatched host. `onRestartHost` asks the host to restart now (its interrupted
/// turns resume like after any interruption); `onCheckForUpdates` updates this app.
struct HostVersionNotice: View {
    let status: HostVersionStatus
    let appVersion: String
    var onRestartHost: () -> Void
    var onCheckForUpdates: () -> Void

    var body: some View {
        switch status {
        case .matched:
            EmptyView()
        case .hostRestartPending(let hostVersion, let workingTasks) where workingTasks > 0:
            NoticeBanner(
                tone: .info,
                systemImage: "arrow.triangle.2.circlepath",
                title: "Native updated to \(appVersion). Its background host switches over when your tasks finish.",
                detail: workingTasks == 1
                    ? "A task is still running on \(hostVersion) and keeps working until it's done."
                    : "\(workingTasks) tasks are still running on \(hostVersion) and keep working until they're done.",
                footnote: "Restarting the host now interrupts them; Native resumes them right after."
            ) {
                Button("Restart Host Now", action: onRestartHost)
                    .buttonStyle(.ds(.secondary))
            }
        case .hostRestartPending:
            NoticeBanner(
                tone: .info,
                systemImage: "arrow.triangle.2.circlepath",
                title: "Native's background host is restarting onto \(appVersion)…"
            ) {
                EmptyView()
            }
        case .appOutdated(let hostVersion):
            NoticeBanner(
                tone: .warning,
                title: "This copy of Native (\(appVersion)) is older than its background host (\(hostVersion))",
                detail: "Update Native so the app and the host match. Your tasks keep running meanwhile."
            ) {
                Button("Check for Updates", action: onCheckForUpdates)
                    .buttonStyle(.ds(.primary))
            }
        }
    }
}
