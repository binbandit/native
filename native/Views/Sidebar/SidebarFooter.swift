import NativePolicy
import SwiftUI

/// The GitHub identity and Settings share the sidebar's bottom row. All in view opens the account
/// (and who manages Native) in place; the classic sidebar leads to Settings.
struct SidebarFooter: View {
    var isAllInView = false
    @Environment(GitHubModel.self) private var gitHub: GitHubModel?
    @Environment(StatusBarRegistry.self) private var statusBar: StatusBarRegistry?

    var body: some View {
        if isAllInView {
            allInView
        } else {
            classic
        }
    }

    private var allInView: some View {
        let isAboveStatusBar = statusBar?.isVisible == true
        return HStack(spacing: DS.Space.md) {
            SidebarAccountButton()
            SettingsButton()
        }
        // The avatar lands 13pt in, the button's own inset before it.
        .padding(.leading, DS.Account.footerLeading - DS.Space.sm)
        .padding(.trailing, DS.Account.footerTrailing - DS.Space.xs)
        .frame(height: isAboveStatusBar ? DS.Size.chromeBar : DS.Account.footerHeight)
        .overlay(alignment: .top) {
            SeparatorLine().padding(.horizontal, DS.Space.lg)
        }
    }

    private var classic: some View {
        let isAboveStatusBar = statusBar?.isVisible == true
        return HStack(spacing: DS.Space.md) {
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

#Preview("All in view footer - Account, managed, managed without an account, signed out") {
    let managed = PolicyCenter(source: StaticPolicySource(managed: SidebarManagedDetailsPreview.northwind.dictionary))
    DSPreviewPair {
        VStack(spacing: 0) {
            SidebarFooter(isAllInView: true)
                .environment(GitHubAccountPreviewFixtures.model(.multiple))
            SidebarFooter(isAllInView: true)
                .environment(GitHubAccountPreviewFixtures.model(.single))
                .environment(managed)
            SidebarFooter(isAllInView: true)
                .environment(GitHubAccountPreviewFixtures.model(.signedOut))
                .environment(managed)
            SidebarFooter(isAllInView: true)
                .environment(GitHubAccountPreviewFixtures.model(.signedOut))
        }
        .frame(width: DS.Size.sidebarWidth)
    }
    .sidebarPreviewEnvironment(AppModel.preview())
}

#Preview("Sidebar footer - Signed out") {
    DSPreviewPair {
        SidebarFooter().frame(width: DS.Size.sidebarWidth)
    }
    .sidebarPreviewEnvironment(AppModel.preview())
    .environment(GitHubAccountPreviewFixtures.model(.signedOut))
}
#endif
