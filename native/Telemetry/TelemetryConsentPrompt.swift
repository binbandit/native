import SwiftUI

extension View {
    /// Asks once, at a calm moment, whether to share anonymous usage with Native
    /// (`TelemetryCenter.shouldAskForConsent`).
    func telemetryConsentPrompt(isTurnRunning: Bool) -> some View {
        modifier(TelemetryConsentPrompt(isTurnRunning: isTurnRunning))
    }
}

private struct TelemetryConsentPrompt: ViewModifier {
    let isTurnRunning: Bool

    @Environment(TelemetryCenter.self) private var telemetry
    @State private var isAsking = false

    func body(content: Content) -> some View {
        content
            .onChange(of: telemetry.shouldAskForConsent(isTurnRunning: isTurnRunning), initial: true) { _, should in
                guard should else { return }
                telemetry.markAskedForConsent()
                isAsking = true
            }
            .alert("Help Improve Native?", isPresented: $isAsking) {
                Button("Share Anonymous Usage") { telemetry.setConsent(true) }
                Button("Not Now", role: .cancel) { telemetry.setConsent(false) }
            } message: {
                Text(
                    "Native can send which features you use, how long it takes to launch, when it stops responding, and which agent versions you run. Never prompts, code, file names or commands. You can change this any time in Settings ▸ Privacy."
                )
            }
    }
}
