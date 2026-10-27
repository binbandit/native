#if DEBUG
import NativeHostClient
import NativeHostProtocol
import SwiftUI

/// Inert row states for design checks: -hostRestartFixture idle|waiting|restarting|done|failed.
/// Omit the argument for behavior checks; fixture actions never request a restart.
enum HostRestartPreviewFixtures {
    static var rowState: BackgroundHostRestartModel.State? {
        switch UserDefaults.standard.string(forKey: "hostRestartFixture") {
        case "idle": .idle
        case "confirming": .confirming
        case "waiting": .waiting
        case "restarting": .restarting
        case "done": .done(.now)
        case "failed": .failed("The host hasn't reconnected. Native keeps trying.")
        default: nil
        }
    }

    static func confirming(busy: Bool) -> some View {
        let host = DurableHost()
        host.manualRestart.request()
        if busy {
            host.upsert(
                HostSessionSummary(
                    id: HostSessionID(), agentID: "claude-code", agentName: "Claude Code", agentSessionID: nil,
                    cwd: "/tmp", title: "Check the build", phase: .prompting))
        }
        return HostRestartSettingsRow(state: .confirming, isAvailable: true, request: {})
            .settingsPreviewPage()
            .hostRestartConfirmation(host)
            .environment(AppModel.preview())
    }
}

#Preview("Background host restart - Confirm idle") {
    DSPreviewPair { HostRestartPreviewFixtures.confirming(busy: false) }
}

#Preview("Background host restart - Confirm busy") {
    DSPreviewPair { HostRestartPreviewFixtures.confirming(busy: true) }
}
#endif
