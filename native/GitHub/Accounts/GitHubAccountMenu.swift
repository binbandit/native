import GitHub
import SwiftUI

/// A menu-shaped popover keeps avatars and recovery guidance readable, with the same arrow-key
/// behavior as the design system's icon picker.
struct GitHubAccountMenu: View {
    @Environment(GitHubModel.self) private var gitHub
    @Environment(SettingsPresentation.self) private var settings
    @FocusState private var isFocused: Bool
    @State private var highlighted: String?

    private var accounts: GitHubAccountsModel { gitHub.accounts }
    private var actions: [String] { accounts.accounts.map(accounts.key) + ["add", "refresh", "settings"] }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text("GitHub Account")
                .font(.dsCaptionMedium)
                .foregroundStyle(.dsTextSecondary)
                .padding(.horizontal, DS.Space.md)
                .padding(.vertical, DS.Space.sm)
            if let guidance = accounts.guidance {
                Text(guidance)
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(DS.Space.md)
            }
            ScrollViewReader { scroller in
                ScrollView {
                    VStack(spacing: DS.Space.xxs) {
                        ForEach(accounts.accounts, id: \.self) { account in
                            accountRow(account).id(accounts.key(account))
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: DS.Size.popoverWidth)
                .fixedSize(horizontal: false, vertical: true)
                .onChange(of: highlighted) { _, id in if let id { scroller.scrollTo(id) } }
            }
            if !accounts.accounts.isEmpty { SeparatorLine().padding(.vertical, DS.Space.xs) }
            action("add", title: "Add GitHub Account…", symbol: "person.badge.plus")
            if accounts.showsSignIn || accounts.accounts.isEmpty, !accounts.isLoading {
                Text(
                    accounts.error == .notInstalled
                        ? "Run in a terminal, then check again:" : "Run in a terminal and follow the sign-in prompts:"
                )
                .font(.dsCaption)
                .foregroundStyle(.dsTextSecondary)
                .padding(.horizontal, DS.Space.md)
                CommandSnippet(command: accounts.signInCommand) { accounts.copySignInCommand() }
                    .padding(.horizontal, DS.Space.md)
                if accounts.copiedCommand {
                    Text("Copied").font(.dsCaption).foregroundStyle(.dsTextSecondary).padding(.horizontal, DS.Space.md)
                }
            }
            action("refresh", title: gitHub.isRefreshing ? "Checking…" : "Check Again", symbol: "arrow.clockwise")
                .disabled(!gitHub.canSwitchAccount)
            action("settings", title: "Manage in Settings", symbol: "gearshape")
            Text("Account choices apply only to Native.")
                .font(.dsCaption)
                .foregroundStyle(.dsTextTertiary)
                .padding(DS.Space.md)
        }
        .padding(DS.Space.xs)
        .frame(width: DS.Size.hoverCardWidth)
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { move(-1) }
        .onKeyPress(.downArrow) { move(1) }
        .onKeyPress(.return) { chooseHighlighted() }
        .onKeyPress(.space) { chooseHighlighted() }
        .onKeyPress(.escape) {
            accounts.isMenuPresented = false; return .handled
        }
        .onAppear {
            highlighted = accounts.current.map(accounts.key) ?? "add"; isFocused = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("GitHub accounts")
    }

    private func accountRow(_ account: AuthStatus.Account) -> some View {
        Button {
            choose(accounts.key(account))
        } label: {
            HStack(spacing: DS.Space.md) {
                GitHubAccountAvatar(name: accounts.name(account), data: accounts.avatar(account))
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(accounts.name(account)).font(.dsBody).foregroundStyle(.dsTextPrimary)
                    Text("@\(account.login)" + (account.host == "github.com" ? "" : " · \(account.host)"))
                        .font(.dsCaption).foregroundStyle(.dsTextSecondary)
                }
                .lineLimit(1)
                Spacer(minLength: DS.Space.sm)
                if accounts.isSelected(account) {
                    Image(systemName: "checkmark").font(.dsCaptionMedium).foregroundStyle(.dsAccentText)
                }
            }
            .padding(DS.Space.md)
            .background(
                highlighted == accounts.key(account) ? Color.dsHover : .clear, in: .rect(cornerRadius: DS.Radius.row)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!gitHub.canSwitchAccount)
        .onHover { if $0 { highlighted = accounts.key(account) } }
        .accessibilityLabel("\(accounts.name(account)), @\(account.login), \(account.host)")
        .accessibilityAddTraits(accounts.isSelected(account) ? .isSelected : [])
    }

    private func action(_ id: String, title: String, symbol: String) -> some View {
        Button {
            choose(id)
        } label: {
            Label(title, systemImage: symbol)
                .font(.dsBody)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DS.Space.md)
                .background(highlighted == id ? Color.dsHover : .clear, in: .rect(cornerRadius: DS.Radius.row))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { if $0 { highlighted = id } }
    }

    private func move(_ step: Int) -> KeyPress.Result {
        let index = highlighted.flatMap { actions.firstIndex(of: $0) } ?? -1
        highlighted = actions[min(max(index + step, 0), actions.count - 1)]
        return .handled
    }

    private func chooseHighlighted() -> KeyPress.Result {
        guard let highlighted else { return .ignored }
        choose(highlighted)
        return .handled
    }

    private func choose(_ id: String) {
        switch id {
        case "add": accounts.addAccount()
        case "refresh": Task { await gitHub.checkAccounts() }
        case "settings": accounts.isMenuPresented = false; settings.open(.gitHub)
        default:
            if let account = accounts.accounts.first(where: { accounts.key($0) == id }) {
                Task { await gitHub.selectAccount(account) }
            }
        }
    }
}

#if DEBUG
#Preview("GitHub account menu - Multiple accounts") {
    DSPreviewPair { GitHubAccountMenu() }
        .environment(GitHubAccountPreviewFixtures.model(.multiple))
        .environment(SettingsPresentation())
}

#Preview("GitHub account menu - Sign in") {
    DSPreviewPair { GitHubAccountMenu() }
        .environment(GitHubAccountPreviewFixtures.model(.signedOut))
        .environment(SettingsPresentation())
}
#endif
