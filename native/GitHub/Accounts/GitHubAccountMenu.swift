import GitHub
import SwiftUI

/// The accounts behind the sidebar's identity, chosen in place: each signed-in account with a check
/// on the one Native uses, then the way to add one and the full controls in Settings. A switch that
/// can't happen here (gh holds another account active) says why under the list.
struct GitHubAccountMenu: View {
    @Environment(GitHubModel.self) private var gitHub
    @Environment(SettingsPresentation.self) private var settings
    /// Closes the popover before something else takes over (Settings).
    let dismiss: () -> Void

    private var accounts: GitHubAccountsModel { gitHub.accounts }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("GitHub Account")
                .font(.dsCaptionMedium)
                .foregroundStyle(.dsTextTertiary)
                .padding(.horizontal, DS.Space.md)
                .frame(height: DS.Account.menuRowHeight)
                .accessibilityAddTraits(.isHeader)
            ForEach(accounts.accounts, id: \.self) { account in
                GitHubAccountMenuRow(account: account)
            }
            SeparatorLine().padding(.horizontal, DS.Space.md).padding(.vertical, DS.Space.xs)
            GitHubAccountMenuItem("Add GitHub Account…") {
                dismiss()
                accounts.addAccount()
                settings.open(.general, revealing: GitHubAccountsSettingsSection.accountsRow)
            }
            GitHubAccountMenuItem("Manage in Settings…", shortcut: "⌘,") {
                dismiss()
                settings.open(.general, revealing: GitHubAccountsSettingsSection.accountsRow)
            }
            if let guidance = accounts.guidance {
                Text(guidance)
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, DS.Space.md)
                    .padding(.top, DS.Space.md)
                    .padding(.bottom, DS.Space.xs)
            }
        }
        .padding(DS.Account.menuInset)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("GitHub accounts")
    }
}

/// One signed-in account: avatar, name, and login on its host, checked when Native uses it.
private struct GitHubAccountMenuRow: View {
    @Environment(GitHubModel.self) private var gitHub
    let account: AuthStatus.Account
    @State private var isHovered = false

    var body: some View {
        let accounts = gitHub.accounts
        let isCurrent = accounts.current.map { $0.host == account.host && $0.login == account.login } ?? false
        Button {
            Task { await gitHub.selectAccount(account) }
        } label: {
            HStack(spacing: DS.Space.md + DS.Space.xxs) {
                GitHubAccountAvatar(
                    name: accounts.name(account), data: accounts.avatar(account), size: DS.Account.menuAvatarSize)
                VStack(alignment: .leading, spacing: 0) {
                    Text(accounts.name(account))
                        .font(.dsCalloutMedium)
                        .foregroundStyle(.dsTextPrimary)
                    Text("\(account.login) · \(account.host)")
                        .font(DS.Account.menuLoginFont)
                        .foregroundStyle(.dsTextTertiary)
                }
                .lineLimit(1)
                Spacer(minLength: DS.Space.md)
                if accounts.switchingTo == accounts.key(account) {
                    DotGridLoader(pattern: .waiting)
                        .frame(width: DS.Size.statusGlyph, height: DS.Size.statusGlyph)
                        .foregroundStyle(.dsTextSecondary)
                } else if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.dsCaptionMedium)
                        .foregroundStyle(.dsTextPrimary)
                }
            }
            .padding(.horizontal, DS.Space.md)
            .padding(.vertical, DS.Space.sm)
            .background(
                isCurrent || isHovered ? Color.dsSelected : .clear,
                in: .rect(cornerRadius: DS.Account.menuRowRadius)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .trackHover($isHovered)
        .disabled(!gitHub.canSwitchAccount)
        .accessibilityLabel("\(accounts.name(account)), @\(account.login), \(account.host)")
        .accessibilityValue(isCurrent ? "Selected" : "")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .accessibilityHint("Use this GitHub account in Native")
    }
}

/// A plain menu line, its shortcut (if any) at the trailing edge.
private struct GitHubAccountMenuItem: View {
    let title: String
    var shortcut: String?
    let action: () -> Void
    @State private var isHovered = false

    init(_ title: String, shortcut: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.shortcut = shortcut
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(.dsCallout).foregroundStyle(.dsTextPrimary)
                Spacer(minLength: DS.Space.xxl)
                if let shortcut {
                    Text(shortcut).font(.dsCallout).foregroundStyle(.dsTextTertiary)
                }
            }
            .padding(.horizontal, DS.Space.md)
            .frame(height: DS.Account.menuRowHeight)
            .background(isHovered ? Color.dsSelected : .clear, in: .rect(cornerRadius: DS.Radius.row))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .trackHover($isHovered)
    }
}

#if DEBUG
#Preview("GitHub account menu - One, two, and a failed switch") {
    DSPreviewPair {
        HStack(alignment: .top, spacing: DS.Space.xl) {
            ForEach([GitHubAccountPreviewFixtures.State.single, .multiple, .failedSwitch], id: \.self) { state in
                GitHubAccountMenu {}
                    .environment(GitHubAccountPreviewFixtures.model(state))
                    .frame(width: DS.Account.menuWidth)
                    .dsOverlayBackground(in: .rect(cornerRadius: DS.Radius.panel))
            }
        }
        .padding(DS.Space.lg)
    }
    .environment(SettingsPresentation())
}
#endif
