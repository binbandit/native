import NativeHostClient
import SwiftUI

// `HostVersionStatus` lives in NativeHostClient, where its comparison is tested.

/// The banner for a mismatched host. `onRestartHost` asks to restart the host now, which confirms
/// first while tasks work (`hostRestartConfirmation`); `onCheckForUpdates` updates this app.
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
                title: "Native updated to \(appVersion). The update finishes when your tasks are idle.",
                detail: workingTasks == 1
                    ? "A task is still running on \(hostVersion) and keeps working until it's done."
                    : "\(workingTasks) tasks are still running on \(hostVersion) and keep working until they're done.",
                footnote: workingTasks == 1
                    ? "Restarting now interrupts it; Native resumes it right after."
                    : "Restarting now interrupts them; Native resumes them right after."
            ) {
                Button("Restart Now…", action: onRestartHost)
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

#if NATIVE_PREVIEWS_WIP
#Preview("Host version notices") {
    DSPreviewPair {
        VStack(spacing: DS.Space.lg) {
            HostVersionNotice(
                status: .hostRestartPending(hostVersion: "1.4.0 (212)", workingTasks: 1), appVersion: "1.4.1 (215)",
                onRestartHost: {}, onCheckForUpdates: {})
            HostVersionNotice(
                status: .hostRestartPending(hostVersion: "1.4.0 (212)", workingTasks: 3), appVersion: "1.4.1 (215)",
                onRestartHost: {}, onCheckForUpdates: {})
            HostVersionNotice(
                status: .hostRestartPending(hostVersion: "1.4.0 (212)", workingTasks: 0), appVersion: "1.4.1 (215)",
                onRestartHost: {}, onCheckForUpdates: {})
            HostVersionNotice(
                status: .appOutdated(hostVersion: "1.5.0 (230)"), appVersion: "1.4.1 (215)", onRestartHost: {},
                onCheckForUpdates: {})
        }
        .frame(width: 640)
    }
}
#endif
