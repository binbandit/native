#if DEBUG
import Foundation
import NativeHostProtocol
import NativeLink
import NativePolicy
import SwiftUI

/// Fixtures for the previews.
private enum AddHostPreview {
    static let offer = AddHostOffer(
        invite: PairingInvite(
            hostID: RemoteHostID(), hostKey: LinkIdentity().publicKey, secret: Data(repeating: 1, count: 32),
            hostName: "Mac mini", expiresAt: .now.addingTimeInterval(272),
            addresses: [
                LinkAddress(kind: .lan, host: "192.168.1.20", port: 47_118),
                LinkAddress(kind: .tailnet, host: "mac-mini.tail1234.ts.net", port: 47_118),
                LinkAddress(kind: .bonjour, host: "Mac mini"),
            ],
            grants: AddHostModel.sshOffer),
        sshDestination: "me@mac-mini.local", hostBuild: PeerInfo(name: "Native Host", version: "1.4.0", build: "140"))

    static func model(_ phase: AddHostModel.Phase, approvalPage: URL? = nil) -> AddHostModel {
        let center = PolicyCenter(source: StaticPolicySource())
        let policy = RemoteHostsPolicy(center: center, isFeatureOn: true)
        return AddHostModel(
            register: { _ in }, environment: { [:] }, input: "me@mac-mini.local", phase: phase,
            approvalPage: approvalPage, policy: policy)
    }

    static func blocked(name: String?, contact: String? = nil) -> AddHostModel {
        var managed: [String: Any] = ["policy.remoteHosts.enabled": false]
        managed["policy.organization.name"] = name
        managed["policy.organization.contact"] = contact
        let center = PolicyCenter(source: StaticPolicySource(managed: managed))
        return AddHostModel(
            register: { _ in }, environment: { [:] }, input: "me@mac-mini.local",
            phase: .failed(.organizationTurnedOff(name: name)),
            policy: RemoteHostsPolicy(center: center, isFeatureOn: true))
    }
}

#Preview("Add Host") {
    DSPreviewPair {
        AddHostSheet(model: AddHostPreview.model(.entering), close: {})
    }
}

#Preview("Confirm") {
    DSPreviewPair {
        AddHostSheet(model: AddHostPreview.model(.confirming(AddHostPreview.offer)), close: {})
    }
}

#Preview("Approve") {
    DSPreviewPair {
        AddHostSheet(
            model: AddHostPreview.model(
                .reaching(destination: "me@mac-mini.local"),
                approvalPage: URL(string: "https://login.tailscale.com/a/l1b2c3")),
            close: {})
    }
}

#Preview("Pairing") {
    DSPreviewPair {
        AddHostSheet(model: AddHostPreview.model(.pairing(AddHostPreview.offer)), close: {})
    }
}

#Preview("Paired") {
    DSPreviewPair {
        AddHostSheet(
            model: AddHostPreview.model(
                .paired(name: "Mac mini", grants: LinkGrants(manageHost: true, runCommands: true))),
            close: {})
    }
}

#Preview("Failed") {
    DSPreviewPair {
        AddHostSheet(model: AddHostPreview.model(.failed(.sshSignIn(destination: "me@mac-mini.local"))), close: {})
    }
}

#Preview("Add Host - Turned off by organization") {
    DSPreviewPair {
        AddHostSheet(
            model: AddHostPreview.blocked(name: "Northwind Federal IT"), close: {})
    }
}

#Preview("Add Host - Turned off by unnamed organization") {
    DSPreviewPair {
        AddHostSheet(model: AddHostPreview.blocked(name: nil), close: {})
    }
}

#Preview("Add Host - Organization help contact") {
    DSPreviewPair {
        AddHostSheet(model: AddHostPreview.blocked(name: "Northwind Federal IT", contact: "#it-help"), close: {})
    }
}

#Preview("Add Host - Organization allows pairing again") {
    DSPreviewPair {
        AddHostSheet(
            model: AddHostPreview.model(.failed(.organizationTurnedOff(name: "Northwind Federal IT"))), close: {})
    }
}
#endif
