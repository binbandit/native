import GitHub
import SwiftUI

/// Account controls live in General; the Go command can reveal this group directly.
struct GitHubAccountsSettingsSection: View {
    init(showsSignOut: Bool = false) {
        _showsSignOut = State(initialValue: showsSignOut)
    }

    static let accountsRow = SettingsRowID("general.github-accounts")
    static var searchEntry: SettingsSearchEntry {
        SettingsSearchEntry(
            id: accountsRow, title: "GitHub accounts",
            description: "Choose the GitHub account Native uses.",
            keywords: ["login", "sign in", "sign out", "logout", "switch", "add", "gh"])
    }

    @State private var showsSignOut = false
    @Environment(GitHubModel.self) private var gitHub
    private var accounts: GitHubAccountsModel { gitHub.accounts }
    private var isChecking: Bool {
        accounts.isLoading || accounts.status == nil && accounts.error == nil
    }
    private var showsCommand: Bool {
        accounts.showsSignIn || accounts.accounts.isEmpty && !isChecking
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            SettingsGroup(
                title: "Accounts",
                footer:
                    "GitHub CLI manages sign-in. To use another account, activate it with gh auth switch in a terminal, then check again."
            ) {
                ForEach(accounts.accounts, id: \.self) { account in
                    accountRow(account)
                }
                if accounts.accounts.isEmpty {
                    SettingsRow(emptyTitle) {
                        if isChecking {
                            DotGridLoader(pattern: .waiting)
                                .frame(width: DS.Size.statusGlyph, height: DS.Size.statusGlyph)
                                .foregroundStyle(.dsTextSecondary)
                        } else {
                            addButton
                        }
                    }
                }
                if !accounts.accounts.isEmpty || isChecking {
                    HStack {
                        addButton
                        if !accounts.accounts.isEmpty {
                            Button("Sign Out…") { showsSignOut.toggle() }
                                .buttonStyle(.settings)
                        }
                        Spacer(minLength: DS.Space.md)
                        checkButton
                    }
                } else {
                    checkButton
                }
            }
            .settingsRevealTarget(Self.accountsRow)
            if showsSignOut {
                SettingsNote("Sign out of GitHub") {
                    Text(
                        "Run this in a terminal and choose the account to sign out, then check again. This also signs that account out of GitHub CLI on this Mac."
                    )
                    CommandSnippet(command: accounts.signOutCommand) { accounts.copySignOutCommand() }
                }
            }
            if let guidance = accounts.guidance {
                SettingsFooter(guidance)
            }
            if showsCommand {
                VStack(alignment: .leading, spacing: DS.Space.md) {
                    CommandSnippet(command: accounts.signInCommand) { accounts.copySignInCommand() }
                    if accounts.copiedCommand {
                        Text("Copied").font(DS.Settings.caption).foregroundStyle(.dsTextSecondary)
                    }
                    if accounts.guidance == nil {
                        SettingsFooter("Run in a terminal and follow the sign-in prompts, then check again.")
                    }
                }
                .padding(.horizontal, DS.Settings.rowInset)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("GitHub accounts")
    }

    private var emptyTitle: String {
        if isChecking { return "Checking GitHub…" }
        if accounts.error == .notInstalled { return "GitHub CLI isn't installed" }
        if case .notAuthenticated = accounts.error { return "Not signed in to GitHub" }
        if accounts.error != nil { return "GitHub isn't available" }
        return "Not signed in to GitHub"
    }

    private var addButton: some View {
        Button("Add GitHub Account…") { accounts.addAccount() }
            .buttonStyle(.settings)
    }

    private var checkButton: some View {
        Button(gitHub.isRefreshing ? "Checking…" : "Check Again") {
            Task { await gitHub.checkAccounts() }
        }
        .buttonStyle(.settings)
        .disabled(!gitHub.canSwitchAccount)
    }

    private func accountRow(_ account: AuthStatus.Account) -> some View {
        Button {
            Task { await gitHub.selectAccount(account) }
        } label: {
            HStack(spacing: DS.Space.lg) {
                GitHubAccountAvatar(name: accounts.name(account), data: accounts.avatar(account))
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: DS.Space.md) {
                        accountName(account)
                        accountLogin(account)
                    }
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        accountName(account)
                        accountLogin(account)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: DS.Space.md)
                if accounts.switchingTo == accounts.key(account) {
                    DotGridLoader(pattern: .waiting)
                        .frame(width: DS.Size.statusGlyph, height: DS.Size.statusGlyph)
                } else if accounts.isSelected(account) {
                    Image(systemName: "checkmark")
                        .font(.dsCaptionMedium)
                }
            }
            .foregroundStyle(.dsTextPrimary)
            .frame(minHeight: DS.Size.controlSM)
            .contentShape(.rect)
            .dsHitTarget(DS.Size.controlSM)
        }
        .buttonStyle(.plain)
        .disabled(!gitHub.canSwitchAccount)
        .accessibilityLabel("\(accounts.name(account)), @\(account.login), \(account.host)")
        .accessibilityValue(accounts.isSelected(account) ? "Selected" : "")
        .accessibilityAddTraits(accounts.isSelected(account) ? .isSelected : [])
        .accessibilityHint("Use this GitHub account in Native")
    }

    private func accountName(_ account: AuthStatus.Account) -> some View {
        Text(accounts.name(account)).font(DS.Settings.body)
    }

    private func accountLogin(_ account: AuthStatus.Account) -> some View {
        Text("@\(account.login)" + (account.host == "github.com" ? "" : " · \(account.host)"))
            .font(DS.Settings.caption)
            .foregroundStyle(.dsTextSecondary)
    }
}

#if DEBUG
#Preview("GitHub accounts - Every state") {
    DSPreviewPair {
        ScrollView {
            VStack(spacing: DS.Space.xxl) {
                ForEach(GitHubAccountPreviewFixtures.State.allCases) { state in
                    GitHubAccountsSettingsSection()
                        .environment(GitHubAccountPreviewFixtures.model(state))
                }
            }
            .settingsPreviewPage()
        }
    }
    .environment(\.settingsPlainly, true)
}

#Preview("GitHub accounts - Narrow") {
    DSPreviewPair {
        GitHubAccountsSettingsSection()
            .environment(GitHubAccountPreviewFixtures.model(.longName))
            .settingsPreviewPage(width: 360)
    }
    .environment(\.settingsPlainly, true)
}
#Preview("GitHub accounts - Sign out") {
    DSPreviewPair {
        GitHubAccountsSettingsSection(showsSignOut: true)
            .environment(GitHubAccountPreviewFixtures.model(.multiple))
            .settingsPreviewPage()
    }
}
#endif
