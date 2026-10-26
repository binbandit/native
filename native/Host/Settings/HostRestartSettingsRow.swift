import NativeHostClient
import SwiftUI

/// Feedback stays beside the action, including when it came from the Native menu.
struct HostRestartSettingsRow: View {
    let state: BackgroundHostRestartModel.State
    let isAvailable: Bool
    let request: () -> Void

    var blockingTasks: [String] = []
    var isHostConnected = false

    @Environment(\.settingsPlainly) private var plainly

    var body: some View {
        if case .failed(let reason) = state {
            ErrorState(
                plainly ? "Couldn't restart the background helper" : "Couldn't restart the background host",
                recovery: isHostConnected
                    ? (plainly ? "The helper is still connected." : "The host is still connected.")
                    : "Native is still trying to reconnect.",
                details: reason,
                primary: isAvailable ? .init("Try Again…", perform: request) : nil
            )
            .settingsRevealTarget(BackgroundSettingsPage.restartRow)
        } else {
            SettingsRow(
                id: BackgroundSettingsPage.restartRow, title: Text("Background host"), plainly: .backgroundHelper,
                description: Text(description),
                accessory: {
                    if state == .waiting {
                        DotGridLoader(pattern: .waiting)
                            .frame(width: DS.Size.statusGlyph, height: DS.Size.statusGlyph)
                            .accessibilityLabel("Waiting for tasks")
                    }
                }
            ) {
                if state == .restarting {
                    progress("Restarting…")
                } else {
                    Button(state == .waiting ? "Restart Now…" : "Restart…", action: request)
                        .buttonStyle(.settings)
                        .disabled(!isAvailable)
                }
            }
        }
    }

    private func progress(_ label: String) -> some View {
        HStack(spacing: DS.Space.sm) {
            DotGridLoader(pattern: .waiting)
                .frame(width: DS.Size.statusGlyph, height: DS.Size.statusGlyph)
            SettingsValue(label)
        }
        .accessibilityElement(children: .combine)
    }

    private var description: String {
        switch state {
        case .idle, .confirming:
            isAvailable
                ? "Tasks reconnect; interrupted turns resume."
                : "Available when agents run in this Mac's background helper."
        case .waiting:
            blockingTasks.isEmpty
                ? "Waiting for tasks to finish before restarting."
                : "Waiting for \(blockingTasks.map { "“\($0)”" }.formatted(.list(type: .and))) to finish."
        case .restarting:
            "Reconnecting tasks."
        case .done(let at):
            "Restarted at \(DSFormat.time(at, now: .now))."
        case .failed:
            ""
        }
    }
}

#if DEBUG
#Preview("Background host restart - Idle") {
    DSPreviewPair { HostRestartSettingsRow(state: .idle, isAvailable: true, request: {}).settingsPreviewPage() }
}

#Preview("Background host restart - Confirming") {
    DSPreviewPair { HostRestartSettingsRow(state: .confirming, isAvailable: true, request: {}).settingsPreviewPage() }
}

#Preview("Background host restart - Waiting") {
    DSPreviewPair {
        HostRestartSettingsRow(state: .waiting, isAvailable: true, request: {}, blockingTasks: ["Check the build"])
            .settingsPreviewPage()
    }
}

#Preview("Background host restart - Restarting") {
    DSPreviewPair { HostRestartSettingsRow(state: .restarting, isAvailable: true, request: {}).settingsPreviewPage() }
}

#Preview("Background host restart - Done") {
    DSPreviewPair { HostRestartSettingsRow(state: .done(.now), isAvailable: true, request: {}).settingsPreviewPage() }
}

#Preview("Background host restart - Failed") {
    DSPreviewPair {
        HostRestartSettingsRow(
            state: .failed("The host hasn't reconnected. Native keeps trying."), isAvailable: true, request: {}
        ).settingsPreviewPage()
    }
}
#endif

#if DEBUG
#Preview("Background host restart - Waiting, narrow Plainly") {
    DSPreviewPair {
        HostRestartSettingsRow(
            state: .waiting, isAvailable: true, request: {},
            blockingTasks: ["Check the build", "Review the changes"]
        ).settingsPreviewPage(width: 320)
    }
    .environment(\.settingsPlainly, true)
}

#Preview("Background host restart - Failed, narrow Plainly") {
    DSPreviewPair {
        HostRestartSettingsRow(
            state: .failed("The background host didn't answer the restart request."),
            isAvailable: true, request: {}
        ).settingsPreviewPage(width: 320)
    }
    .environment(\.settingsPlainly, true)
}
#endif
