import NativePolicy
import SwiftUI

/// Who manages this Native and what that changes about the account footer's world, read from the
/// organization's policy: the organization named once, what it turned off and what that means, and
/// where to ask. Calm, so nothing looks broken.
struct SidebarManagedDetails: View {
    let center: PolicyCenter

    /// What the organization turned off that the footer's account and Macs touch.
    struct Fact: Identifiable {
        let name: String
        let effect: String
        var id: String { name }
    }

    static func facts(_ center: PolicyCenter) -> [Fact] {
        let policy = center.policy
        var facts: [Fact] = []
        if center.isGitHubOutOfReach, center.isNetworkManaged {
            facts.append(Fact(name: "GitHub", effect: "Pull requests and accounts aren't available on this Mac."))
        }
        if !policy.remoteHostsEnabled, policy.isManaged(.remoteHostsEnabled) {
            facts.append(Fact(name: "Other Macs", effect: "Tasks run on this Mac only."))
        }
        if !policy.companionEnabled, policy.isManaged(.companionEnabled) {
            facts.append(Fact(name: "Pairing", effect: "Phones and iPads can't pair with this Mac."))
        }
        return facts
    }

    var body: some View {
        let facts = Self.facts(center)
        VStack(alignment: .leading, spacing: 0) {
            Label {
                Text(center.managementLine)
            } icon: {
                Image(systemName: "building.2").foregroundStyle(.dsTextSecondary)
            }
            .font(.dsCalloutSemibold)
            .foregroundStyle(.dsTextPrimary)
            .accessibilityAddTraits(.isHeader)
            if facts.isEmpty {
                Text("Some of Native's settings are set for you. Settings shows which ones.")
                    .font(.dsCallout)
                    .foregroundStyle(.dsTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DS.Space.sm)
            } else {
                VStack(alignment: .leading, spacing: DS.Space.md) {
                    ForEach(facts) { fact in
                        HStack(alignment: .firstTextBaseline, spacing: DS.Space.md) {
                            Text(fact.name)
                                .font(.dsCalloutMedium)
                                .foregroundStyle(.dsTextPrimary)
                                .frame(width: DS.Account.managedKeyWidth, alignment: .leading)
                            VStack(alignment: .leading, spacing: 0) {
                                Text("Off by policy").font(.dsCallout).foregroundStyle(.dsTextSecondary)
                                Text(fact.effect)
                                    .font(.dsCaption)
                                    .foregroundStyle(.dsTextTertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.top, DS.Space.lg)
                .overlay(alignment: .top) { SeparatorLine() }
                .padding(.top, DS.Space.lg)
            }
            Text(contactLine(count: facts.count))
                .font(.dsCaption)
                .foregroundStyle(.dsTextTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DS.Space.lg)
        }
        .padding(.vertical, DS.Account.managedInset)
        .padding(.horizontal, DS.Account.managedLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private func contactLine(count: Int) -> String {
        let what = count == 1 ? "it" : count == 2 ? "either" : "them"
        return center.policy.organizationContact.map { "Ask in \($0) to change \(what)." }
            ?? "Ask your administrator to change \(what)."
    }
}

#if DEBUG
#Preview("Managed footer details - Named, unnamed, nothing off") {
    DSPreviewPair {
        VStack(spacing: DS.Space.lg) {
            ForEach(SidebarManagedDetailsPreview.cases, id: \.self) { values in
                SidebarManagedDetails(center: PolicyCenter(source: StaticPolicySource(managed: values.dictionary)))
                    .frame(width: DS.Account.managedWidth)
                    .dsOverlayBackground(in: .rect(cornerRadius: DS.Radius.panel))
            }
        }
        .padding(DS.Space.lg)
    }
}

/// Policies for the previews and the sidebar fixture: hashable, so previews can loop over them.
enum SidebarManagedDetailsPreview: Hashable {
    case northwind, unnamed, nothingOff

    static let cases: [Self] = [.northwind, .unnamed, .nothingOff]

    var dictionary: [String: Any] {
        switch self {
        case .northwind:
            [
                PolicyKey.organizationName.rawValue: "Northwind Federal IT",
                PolicyKey.organizationContact.rawValue: "#it-help",
                PolicyKey.remoteHostsEnabled.rawValue: false,
                PolicyKey.companionEnabled.rawValue: false,
            ]
        case .unnamed: [PolicyKey.remoteHostsEnabled.rawValue: false]
        case .nothingOff:
            [
                PolicyKey.organizationName.rawValue: "Northwind Federal IT",
                PolicyKey.scriptsEnabled.rawValue: false,
            ]
        }
    }
}
#endif
