import NativePolicy
import SwiftUI

/// Organization details live with the settings its policy controls.
struct SettingsManagementDetails: View {
    let center: PolicyCenter

    struct Fact: Identifiable {
        let name: String
        let explanation: String
        var id: String { name }
    }

    static func facts(_ center: PolicyCenter) -> [Fact] {
        var facts: [Fact] = []
        if center.isGitHubOutOfReach, center.isNetworkManaged {
            facts.append(
                Fact(
                    name: "GitHub",
                    explanation: "GitHub is off by policy. Pull requests and accounts aren't available on this Mac."))
        }
        if !center.policy.remoteHostsEnabled, center.policy.isManaged(.remoteHostsEnabled) {
            facts.append(
                Fact(name: "Other Macs", explanation: "Other Macs are off by policy. Tasks run on this Mac only."))
        }
        if !center.policy.companionEnabled, center.policy.isManaged(.companionEnabled) {
            facts.append(
                Fact(
                    name: "Pairing", explanation: "Pairing is off by policy. Phones and iPads can't pair with this Mac."
                ))
        }
        return facts
    }

    var body: some View {
        SettingsNote(center.managementLine, systemImage: "building.2") {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                Text("Some of Native's settings are set for you. A lock shows which ones.")
                ForEach(Self.facts(center)) { fact in
                    Text(fact.explanation)
                }
                Text(
                    center.policy.organizationContact.map { "Ask in \($0) to change managed settings." }
                        ?? "Ask your administrator to change managed settings.")
            }
        }
    }
}

#if DEBUG
#Preview("Management in General - Named, unnamed, nothing off") {
    DSPreviewPair {
        VStack(spacing: DS.Space.xxl) {
            ForEach(SettingsManagementPreview.cases, id: \.self) { values in
                SettingsManagementDetails(center: PolicyCenter(source: StaticPolicySource(managed: values.dictionary)))
            }
        }
        .settingsPreviewPage()
    }
}

enum SettingsManagementPreview: Hashable {
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
