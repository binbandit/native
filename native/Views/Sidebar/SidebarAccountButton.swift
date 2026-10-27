import GitHub
import NativePolicy
import SwiftUI

/// All in view's identity in the footer: the GitHub account Native uses, with an up-down chevron
/// that opens the accounts in place. When an organization manages Native, a lock takes the
/// chevron's place and the same popover says who manages it, what that turns off, and where to ask.
/// With no account and no organization, there's nothing to show.
struct SidebarAccountButton: View {
    @Environment(PolicyCenter.self) private var policy: PolicyCenter?
    #if os(macOS)
    @Environment(GitHubModel.self) private var gitHub: GitHubModel?
    #endif
    @State private var isPresented = Self.opensAtLaunch
    @State private var isHovered = false

    /// `-nativeSidebarFixtureAccountOpen YES` opens it at launch, for checks of the popover, whose
    /// footer the accessibility tree reaches only after the whole list.
    private static var opensAtLaunch: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "nativeSidebarFixtureAccountOpen")
        #else
        false
        #endif
    }

    private var isManaged: Bool { policy?.policy.managedKeys.isEmpty == false }

    #if os(macOS)
    /// GitHub's accounts, while one is signed in and its listing isn't an error.
    private var accounts: GitHubAccountsModel? {
        guard let gitHub, gitHub.accounts.current != nil,
            gitHub.accounts.status == nil || !gitHub.accounts.accounts.isEmpty
        else { return nil }
        return gitHub.accounts
    }
    #endif

    var body: some View {
        if hasAccount || isManaged {
            Button {
                isPresented.toggle()
            } label: {
                HStack(spacing: DS.Space.md) {
                    identity
                    Image(systemName: isManaged ? "lock" : "chevron.up.chevron.down")
                        .font(DS.Account.footerTrailingGlyph)
                        .foregroundStyle(.dsTextTertiary)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(isHovered || isPresented ? .dsTextPrimary : .dsTextSecondary)
                .padding(.leading, DS.Space.sm)
                .padding(.trailing, DS.Space.md)
                .frame(height: DS.Size.controlSM)
                .background(
                    isPresented ? Color.dsSelected : isHovered ? .dsHover : .clear,
                    in: .rect(cornerRadius: DS.Radius.row)
                )
                .contentShape(.rect)
                .dsHitTarget(DS.Size.controlSM)
            }
            .buttonStyle(SidebarRowButtonStyle())
            .trackHover($isHovered)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(hasAccount ? "Shows your GitHub accounts" : "Shows what your organization manages")
            .help(accessibilityLabel)
            // Centered on a point that lines its leading edge up with the sidebar's rows, so it opens
            // over the window rather than hanging off its edge.
            .dsPopover(
                isPresented: $isPresented,
                attachmentAnchor: .rect(.rect(CGRect(x: popoverWidth / 2 + popoverLead, y: 0, width: 0, height: 0))),
                arrowEdge: .top
            ) {
                popover
            }
        } else {
            Spacer(minLength: 0)
        }
    }

    private var popoverWidth: CGFloat { isManaged ? DS.Account.managedWidth : DS.Account.menuWidth }

    /// From this button's leading edge to the rows' (the footer insets the button a little less).
    private var popoverLead: CGFloat { DS.Sidebar.inset - (DS.Account.footerLeading - DS.Space.sm) }

    private var hasAccount: Bool {
        #if os(macOS)
        accounts != nil
        #else
        false
        #endif
    }

    @ViewBuilder private var identity: some View {
        #if os(macOS)
        if let accounts, let account = accounts.current {
            GitHubAccountAvatar(name: accounts.name(account), data: accounts.avatar(account))
            Text(accounts.footerName)
                .font(.dsCalloutMedium)
                .tracking(DS.Account.nameTracking)
                .lineLimit(1)
                .truncationMode(.tail)
        } else {
            managedIdentity
        }
        #else
        managedIdentity
        #endif
    }

    /// Without an account, the organization stands in: its building where the avatar goes.
    private var managedIdentity: some View {
        Group {
            Image(systemName: "building.2")
                .font(.dsCaption)
                .foregroundStyle(.dsTextTertiary)
                .frame(width: DS.Account.avatarSize, height: DS.Account.avatarSize)
            Text("Managed")
                .font(.dsCalloutMedium)
                .tracking(DS.Account.nameTracking)
        }
    }

    private var accessibilityLabel: String {
        #if os(macOS)
        if let accounts, let account = accounts.current {
            return "GitHub Account: @\(account.login)" + (isManaged ? ", managed by your organization" : "")
        }
        #endif
        return policy?.managementLine ?? PolicyCenter.managedExplanation
    }

    @ViewBuilder private var popover: some View {
        VStack(alignment: .leading, spacing: 0) {
            #if os(macOS)
            if let gitHub, hasAccount {
                GitHubAccountMenu { isPresented = false }.environment(gitHub)
            }
            #endif
            if let policy, isManaged {
                if hasAccount { SeparatorLine() }
                SidebarManagedDetails(center: policy)
            }
        }
        .frame(width: popoverWidth)
    }
}
