#if os(macOS)
import SwiftUI

/// The Software Update window "Check for Updates…" opens: the same status Settings ▸ Updates shows,
/// in a small window of its own.
struct UpdatesScene: Scene {
    static let windowID = "software-update"

    let controller: UpdateController
    /// The accent palette the rest of the app uses (`dsAccentPalette(themeID:)`).
    let accentThemeID: String

    var body: some Scene {
        Window("Software Update", id: Self.windowID) {
            UpdatesWindowContent(controller: controller)
                .dsAccentPalette(themeID: accentThemeID)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .restorationBehavior(.disabled)
    }
}

private struct UpdatesWindowContent: View {
    let controller: UpdateController

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            HStack(spacing: DS.Space.md) {
                Text(controller.current.channel.displayName)
                    .font(.dsHeadline)
                    .foregroundStyle(.dsTextPrimary)
                if controller.current.channel.isNightly {
                    NightlyMark()
                        .foregroundStyle(.dsTextTertiary)
                }
                Spacer(minLength: 0)
                Text(controller.current.displayVersion)
                    .font(.dsMonoCaption)
                    .foregroundStyle(.dsTextTertiary)
                    .textSelection(.enabled)
            }
            SeparatorLine()
            UpdateStatusView(controller: controller)
        }
        .padding(DS.Space.xl)
        .frame(width: 480, alignment: .topLeading)
        .background(.dsBackground)
    }
}
#endif
