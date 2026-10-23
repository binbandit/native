import SwiftUI

/// A quiet identity that leads to the account controls in General.
struct GitHubAccountButton: View {
    @Environment(GitHubModel.self) private var gitHub
    @Environment(SettingsPresentation.self) private var settings
    @State private var isHovered = false

    var body: some View {
        let accounts = gitHub.accounts
        if let account = accounts.current {
            Button {
                settings.open(.general, revealing: GitHubAccountsSettingsSection.accountsRow)
            } label: {
                HStack(spacing: DS.Space.md) {
                    GitHubAccountAvatar(name: accounts.name(account), data: accounts.avatar(account))
                    Text(displayName)
                        .font(.dsCalloutBook)
                        .tracking(DS.Account.nameTracking)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundStyle(isHovered ? .dsTextPrimary : .dsTextSecondary)
                .padding(.leading, DS.Space.sm)
                .padding(.trailing, DS.Space.md)
                .frame(height: DS.Size.controlSM)
                .background(isHovered ? Color.dsHover : .clear, in: .rect(cornerRadius: DS.Radius.row))
                .contentShape(.rect)
                .dsHitTarget(DS.Size.controlSM)
            }
            .buttonStyle(SidebarRowButtonStyle())
            .trackHover($isHovered)
            .accessibilityLabel("GitHub Account")
            .accessibilityValue("\(accounts.name(account)), @\(account.login)")
            .accessibilityHint("Open Accounts in General settings")
            .help("GitHub Account: @\(account.login)")
        }
    }

    private var displayName: String {
        let accounts = gitHub.accounts
        guard let current = accounts.current else { return "" }
        let name = accounts.name(current)
        let matches = accounts.accounts.filter { accounts.name($0) == name }
        return matches.count > 1 ? "@\(current.login)" : name
    }
}

#if DEBUG
#Preview("GitHub account footer - Every state") {
    DSPreviewPair {
        VStack(spacing: DS.Space.lg) {
            ForEach(GitHubAccountPreviewFixtures.State.allCases) { state in
                GitHubAccountButton()
                    .environment(GitHubAccountPreviewFixtures.model(state))
            }
        }
        .frame(width: DS.Size.sidebarWidth)
        .padding(DS.Space.lg)
    }
    .environment(SettingsPresentation())
}
#endif
