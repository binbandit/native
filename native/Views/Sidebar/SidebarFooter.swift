import NativePolicy
import SwiftUI

/// One full-width Settings button in both sidebar presentations.
struct SidebarFooter: View {
    @Environment(GitHubModel.self) private var gitHub: GitHubModel?
    @Environment(SettingsPresentation.self) private var settings
    @Environment(StatusBarRegistry.self) private var statusBar: StatusBarRegistry?
    @State private var isHovered = false

    private var accounts: GitHubAccountsModel? {
        #if os(macOS)
        guard let accounts = gitHub?.accounts, accounts.current != nil,
            accounts.status == nil || !accounts.accounts.isEmpty
        else { return nil }
        return accounts
        #else
        return nil
        #endif
    }

    var body: some View {
        Button {
            settings.open()
        } label: {
            HStack(spacing: DS.Space.md) {
                if let accounts, let account = accounts.current {
                    GitHubAccountAvatar(name: accounts.name(account), data: accounts.avatar(account))
                    Text(accounts.name(account))
                        .tracking(DS.Account.nameTracking)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else {
                    Text("Settings")
                }
                Spacer(minLength: DS.Space.md)
                Image(systemName: "gearshape")
                    .font(DS.Account.settingsGlyph)
                    .accessibilityHidden(true)
            }
            .font(.dsCalloutMedium)
            .foregroundStyle(isHovered ? .dsTextPrimary : .dsTextSecondary)
            .padding(.leading, DS.Space.sm)
            .padding(.trailing, DS.Space.md)
            .frame(maxWidth: .infinity)
            .frame(height: DS.Size.controlSM)
            .background(isHovered ? Color.dsHover : .clear, in: .rect(cornerRadius: DS.Radius.row))
            .contentShape(.rect)
            .dsHitTarget(DS.Size.controlSM)
        }
        .buttonStyle(SidebarRowButtonStyle())
        .trackHover($isHovered)
        .accessibilityLabel(
            accounts.flatMap { accounts in accounts.current.map { "\(accounts.name($0)), Settings" } } ?? "Settings"
        )
        .accessibilityIdentifier("sidebar.settings")
        .help("Settings")
        .padding(.leading, DS.Account.footerLeading - DS.Space.sm)
        .padding(.trailing, DS.Account.footerTrailing - DS.Space.md)
        .frame(height: statusBar?.isVisible == true ? DS.Size.chromeBar : DS.Account.footerHeight)
        .overlay(alignment: .top) {
            SeparatorLine().padding(.horizontal, DS.Space.lg)
        }
    }
}

#if DEBUG
#Preview("Sidebar footer - Account, loading, signed out, offline, long name, login fallback") {
    DSPreviewPair {
        VStack(spacing: 0) {
            ForEach(GitHubAccountPreviewFixtures.State.allCases) { state in
                SidebarFooter()
                    .environment(GitHubAccountPreviewFixtures.model(state))
            }
        }
        .frame(width: DS.Size.sidebarWidth)
    }
    .sidebarPreviewEnvironment(AppModel.preview())
}

#Preview("Sidebar footer - Managed account and signed out") {
    DSPreviewPair {
        VStack(spacing: 0) {
            SidebarFooter().environment(GitHubAccountPreviewFixtures.model(.single))
            SidebarFooter().environment(GitHubAccountPreviewFixtures.model(.signedOut))
        }
        .frame(width: DS.Size.sidebarWidth)
    }
    .sidebarPreviewEnvironment(AppModel.preview())
    .environment(PolicyCenter(source: StaticPolicySource(managed: SettingsManagementPreview.northwind.dictionary)))
}
#endif
