import NativeHostClient
import SwiftUI

// `HostVersionStatus` lives in NativeHostClient, where its comparison is tested.

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
