import Foundation
import NativeHostProtocol
import Testing

@testable import NativeLink

/// Windows opened by `pair` on a host without a screen: the device that proves the link pairs
/// without anyone confirming, with no more than the link and the device both allow.
@Suite struct PreapprovedPairingTests {
    let mac = LinkDeviceInfo(name: "Laptop", model: "Mac", system: "macOS 27.2")

    @Test func theLinkPairsWithoutAskingAndGivesWhatBothAllow() async throws {
        let records = LinkLocked<[LinkPairingRecord]>([])
        let harness = try GatewayHarness(paired: { record in records.withLock { $0.append(record) } })
        let offered = LinkGrants(manageHost: true, runCommands: true)
        let invite = try #require(await harness.gateway.openPairingWindow(preapproving: offered).pairing?.invite)
        #expect(invite.grants == offered)

        var device = mac
        device.requestedGrants = LinkGrants(managePlugins: true, runCommands: true)
        let (_, result) = try await LinkInitiator.pair(
            over: try harness.connection(), identity: LinkIdentity(), credential: .invite(invite), device: device,
            awaitingConfirmation: { _ in Issue.record("nobody is asked") })

        let given = LinkGrants(runCommands: true)
        #expect(result.grants == given)
        #expect(harness.admitted.withLock { $0.first?.1 } == given)
        let status = await harness.gateway.status
        #expect(status.pairing?.phase == .paired)
        #expect(status.pairing?.request?.device.name == "Laptop")
        #expect(records.value.map(\.wasPreapproved) == [true])
        #expect(records.value.first?.device.grants == given)
        #expect(records.value.first?.summary.contains("run commands and edit files") == true)
    }

    @Test func aDeviceThatAsksNothingGetsItsUsualDefaultsWithinTheLink() async throws {
        let harness = try GatewayHarness()
        let offered = LinkGrants(managePlugins: true, manageHost: true, runCommands: true)
        let invite = try #require(await harness.gateway.openPairingWindow(preapproving: offered).pairing?.invite)
        let (_, result) = try await LinkInitiator.pair(
            over: try harness.connection(), identity: LinkIdentity(), credential: .invite(invite),
            device: harness.device, awaitingConfirmation: { _ in })
        // A phone: installing updates, as when scanning the QR code, and never commands.
        #expect(result.grants == LinkGrants(manageHost: true))
    }

    @Test func theTypedCodeNeverPairsAWindowNobodyWatches() async throws {
        let harness = try GatewayHarness()
        let status = await harness.gateway.openPairingWindow(preapproving: .standard)
        let typed = try #require(status.pairing?.code)
        let code = try #require(PairingCode(typed: typed))
        await #expect(throws: LinkError.refused(.noPairingWindow)) {
            _ = try await LinkInitiator.pair(
                over: try harness.connection(), identity: LinkIdentity(), credential: .code(code),
                device: harness.device, awaitingConfirmation: { _ in })
        }
        #expect(await harness.gateway.status.pairing?.phase == .open)
    }

    @Test func theLinkIsSingleUse() async throws {
        let harness = try GatewayHarness()
        let invite = try #require(await harness.gateway.openPairingWindow(preapproving: .standard).pairing?.invite)
        _ = try await LinkInitiator.pair(
            over: try harness.connection(), identity: LinkIdentity(), credential: .invite(invite), device: mac,
            awaitingConfirmation: { _ in })
        await #expect(throws: LinkError.refused(.noPairingWindow)) {
            _ = try await LinkInitiator.pair(
                over: try harness.connection(), identity: LinkIdentity(), credential: .invite(invite),
                device: mac, awaitingConfirmation: { _ in })
        }
        #expect(await harness.gateway.status.activeDevices.count == 1)
    }

    @Test func pairingsConfirmedOnScreenAreJournaledToo() async throws {
        let records = LinkLocked<[LinkPairingRecord]>([])
        let harness = try GatewayHarness(paired: { record in records.withLock { $0.append(record) } })
        _ = try await harness.pairDevice()
        #expect(records.value.map(\.wasPreapproved) == [false])
        #expect(records.value.first?.summary.contains("Settings › Paired Devices") == true)
    }

    @Test func theLinkCarriesItsGrantsAndOlderLinksStillRead() throws {
        var invite = PairingInvite(
            hostID: HostID(), hostKey: LinkIdentity().publicKey, secret: Data(repeating: 7, count: 32),
            hostName: "Mac mini", expiresAt: Date(timeIntervalSince1970: 1_800_000_300),
            addresses: [LinkAddress(kind: .tailnet, host: "mac-mini.tail1234.ts.net", port: 47_118)],
            grants: LinkGrants(runCommands: true))
        #expect(try PairingInvite(url: invite.url.absoluteString) == invite)
        invite.grants = nil
        #expect(!invite.url.absoluteString.isEmpty)
        #expect(try PairingInvite(url: invite.url.absoluteString).grants == nil)
    }

    @Test func grantsReadAsOneSentence() {
        #expect(LinkGrants.standard.abilities == "follow and drive tasks")
        #expect(LinkGrants(manageHost: true).abilities == "follow and drive tasks and install updates")
        #expect(
            LinkGrants(managePlugins: true, manageHost: true, runCommands: true).abilities
                == "follow and drive tasks, run commands and edit files in its projects, install updates, and turn plugins on and off"
        )
        let all = LinkGrants(managePlugins: true, manageHost: true, runCommands: true)
        #expect(all.intersection(.standard) == .standard)
        #expect(all.intersection(LinkGrants(runCommands: true)) == LinkGrants(runCommands: true))
    }
}
