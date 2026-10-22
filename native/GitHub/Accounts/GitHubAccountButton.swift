import SwiftUI

struct GitHubAccountButton: View {
    @Environment(GitHubModel.self) private var gitHub
    @State private var isHovered = false

    var body: some View {
        @Bindable var accounts = gitHub.accounts
        Button {
            accounts.showMenu()
        } label: {
            HStack(spacing: DS.Space.md) {
                if let account = accounts.current {
                    GitHubAccountAvatar(name: accounts.name(account), data: accounts.avatar(account))
                } else {
                    Image(systemName: "person.crop.circle")
                        .font(.dsCallout)
                        .frame(width: DS.Size.controlXS, height: DS.Size.controlXS)
                }
                Text(accounts.title)
                    .font(.dsCaptionMedium)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if accounts.accounts.count > 1 {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.dsMicro)
                        .foregroundStyle(.dsTextTertiary)
                }
                if accounts.guidance != nil, accounts.current != nil {
                    Image(systemName: "exclamationmark.circle")
                        .font(.dsCaption)
                        .foregroundStyle(.dsTextSecondary)
                }
            }
            .foregroundStyle(isHovered ? .dsTextPrimary : .dsTextSecondary)
            .contentShape(.rect)
            .dsHitTarget(DS.Size.controlXS)
        }
        .buttonStyle(.plain)
        .trackHover($isHovered)
        .accessibilityLabel("GitHub Account")
        .accessibilityValue(accounts.title)
        .accessibilityHint(accounts.guidance ?? "Choose the GitHub account Native uses")
        .help(accounts.guidance ?? "GitHub Account: \(accounts.title)")
        .dsPopover(isPresented: $accounts.isMenuPresented, arrowEdge: .top) {
            GitHubAccountMenu()
        }
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
}
#endif
