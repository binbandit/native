import SwiftUI

/// The GitHub identity and Settings share the sidebar's bottom row.
struct SidebarFooter: View {
    @Environment(GitHubModel.self) private var gitHub: GitHubModel?
    @Environment(StatusBarRegistry.self) private var statusBar: StatusBarRegistry?

    var body: some View {
        let isAboveStatusBar = statusBar?.isVisible == true
        HStack(spacing: DS.Space.md) {
            #if os(macOS)
            if let gitHub, gitHub.accounts.current != nil,
                gitHub.accounts.status == nil || !gitHub.accounts.accounts.isEmpty
            {
                GitHubAccountButton().environment(gitHub)
            } else {
                Spacer(minLength: 0)
            }
            #else
            Spacer(minLength: 0)
            #endif
            SettingsButton()
        }
        .padding(.horizontal, DS.Space.md)
        .padding(.vertical, isAboveStatusBar ? 0 : DS.Space.lg)
        .frame(height: isAboveStatusBar ? DS.Size.chromeBar : nil)
        .overlay(alignment: .top) {
            SeparatorLine()
                .padding(.horizontal, DS.Space.lg)
        }
    }
}

/// Opens Settings (a gear, "Settings ⌘,"). iPadOS has no Settings scene; the
/// app presents settings there itself, so the gear isn't shown.
private struct SettingsButton: View {
    @Environment(SettingsPresentation.self) private var settings

    var body: some View {
        Button {
            settings.open()
        } label: {
            FooterGlyph(systemImage: "gearshape")
        }
        .buttonStyle(SidebarRowButtonStyle())
        .help("Settings (⌘,)")
        .accessibilityLabel("Settings")
    }
}

/// The Settings cog shares the identity's row height and hover treatment.
private struct FooterGlyph: View {
    let systemImage: String

    @State private var isHovered = false

    var body: some View {
        Image(systemName: systemImage)
            .font(DS.Account.settingsGlyph)
            .foregroundStyle(isHovered ? .dsTextPrimary : .dsTextSecondary)
            .frame(width: DS.Size.controlSM, height: DS.Size.controlSM)
            .background(isHovered ? Color.dsHover : .clear, in: .rect(cornerRadius: DS.Radius.row))
            .contentShape(.rect)
            .dsHitTarget(DS.Size.controlSM)
            .trackHover($isHovered)
    }
}

#if DEBUG
#Preview("Sidebar footer") {
    DSPreviewPair {
        SidebarFooter()
            .frame(width: DS.Size.sidebarWidth)
    }
    .sidebarPreviewEnvironment(AppModel.preview())
    .environment(GitHubAccountPreviewFixtures.model(.multiple))
}

#Preview("Sidebar footer - Signed out") {
    DSPreviewPair {
        SidebarFooter().frame(width: DS.Size.sidebarWidth)
    }
    .sidebarPreviewEnvironment(AppModel.preview())
    .environment(GitHubAccountPreviewFixtures.model(.signedOut))
}
#endif
