import SwiftUI

/// Over the terminal while the user's Ghostty config doesn't load: why, the way to the details, and
/// Reload.
struct TerminalConfigNotice: View {
    let diagnostics: [String]
    let reload: () -> Void
    @Environment(SettingsPresentation.self) private var settings

    var body: some View {
        NoticeBanner(
            tone: .warning,
            title: "Your Ghostty config didn't load, so Native's terminal settings are in use",
            detail: diagnostics.first
        ) {
            Button("Show All") { settings.open(.terminal) }
                .buttonStyle(.ds(.ghost))
            Button("Reload", action: reload)
                .buttonStyle(.ds(.secondary))
        }
        .padding(.horizontal, DS.Space.md)
        .padding(.bottom, DS.Space.xs)
    }
}
