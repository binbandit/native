import NativeHostClient
import SwiftUI

/// Feedback stays beside the action, including when it came from the Native menu.
struct HostRestartSettingsRow: View {
    let state: BackgroundHostRestartModel.State
    let isAvailable: Bool
    let request: () -> Void

    var body: some View {
        SettingsRow(
            id: BackgroundSettingsPage.restartRow, "Restart background host",
            description: Text(description)
        ) {
            if state.isBusy {
                HStack(spacing: DS.Space.sm) {
                    DotGridLoader(pattern: .waiting)
                        .frame(width: DS.Size.statusGlyph, height: DS.Size.statusGlyph)
                    SettingsValue(state == .waiting ? "Waiting for tasks…" : "Restarting…")
                }
                .accessibilityElement(children: .combine)
            } else {
                Button(buttonTitle, action: request)
                    .buttonStyle(.settings)
                    .disabled(!isAvailable)
            }
        }
    }

    private var buttonTitle: String {
        if case .failed = state { "Try Again…" } else { "Restart Background Host…" }
    }

    private var description: String {
        switch state {
        case .idle, .confirming:
            isAvailable
                ? "Restart this Mac's host. Your tasks reconnect and interrupted turns resume."
                : "Available when this Mac runs agents in its background host."
        case .waiting:
            "The host restarts once running and waiting tasks finish. Your tasks keep working until then."
        case .restarting:
            "Restarting this Mac's host and reconnecting your tasks…"
        case .done(let at):
            "Restarted at \(DSFormat.time(at, now: .now)). Your tasks reconnect and interrupted turns resume."
        case .failed(let reason):
            "Couldn't restart the background host. \(reason) Try again."
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
    DSPreviewPair { HostRestartSettingsRow(state: .waiting, isAvailable: true, request: {}).settingsPreviewPage() }
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
