import Foundation
import NativeHostProtocol
import Testing

@testable import NativeLink

@Suite struct PairingTests {
    @Test func pairsWithTheInviteAndServesTheHostProtocol() async throws {
        let harness = try GatewayHarness()
        let (host, channel) = try await harness.pairDevice()
        #expect(host.machineName == "Test Mac")
        #expect(host.hostKey == (await harness.gateway.status.hostKey))
        let status = await harness.gateway.status
        #expect(status.pairing?.phase == .paired)
        #expect(status.activeDevices.map(\.device.name) == ["Test iPhone"])
        #expect(status.activeDevices.first?.isConnected == true)
        #expect(status.isEnabled)

        // The channel now carries the host protocol, with the device's name as the host knows it.
        let initialize =
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1,"clientInfo":{"name":"spoofed","version":"1","build":"1"}}}"#
        channel.write(Data((initialize + "\n").utf8))
        let (stream, grants) = try #require(harness.admitted.withLock { $0.first })
        #expect(grants == .standard)
        var lines = stream.incoming().makeAsyncIterator()
        let forwarded = try #require(await lines.next())
        let text = String(decoding: forwarded, as: UTF8.self)
        #expect(text.contains(#""name":"Test iPhone""#))
        #expect(!text.contains("spoofed"))
    }

    @Test func refusesMethodsBeyondTheDevicesGrants() async throws {
        let harness = try GatewayHarness()
        let (_, channel) = try await harness.pairDevice()
        // The host reads the device's stream; the policy runs as it does.
        let (stream, _) = try #require(harness.admitted.withLock { $0.first })
        let reading = Task { for await _ in stream.incoming() {} }
        defer { reading.cancel() }
        var replies = channel.incoming().makeAsyncIterator()
        channel.write(
            Data(
                #"{"jsonrpc":"2.0","id":7,"method":"_native/host/shutdown","params":{"stopAgents":true}}"#.utf8 + [0x0A]
            ))
        let reply = String(decoding: try #require(await replies.next()), as: UTF8.self)
        #expect(reply.contains(#""id":7"#))
        #expect(reply.contains("-32601"))
        #expect(!LinkMethodPolicy.allows(HostProtocol.Method.setPluginEnabled, with: .standard))
        #expect(LinkMethodPolicy.allows(HostProtocol.Method.setPluginEnabled, with: LinkGrants(managePlugins: true)))
        #expect(!LinkMethodPolicy.allows(HostProtocol.Method.syncAgents, with: LinkGrants(managePlugins: true)))
        #expect(!LinkMethodPolicy.allows("_native/exec/run", with: LinkGrants(managePlugins: true)))
        #expect(!LinkMethodPolicy.allows(HostProtocol.Method.updateInstall, with: .standard))
        #expect(LinkMethodPolicy.allows(HostProtocol.Method.updateInstall, with: LinkGrants(manageHost: true)))
        #expect(LinkMethodPolicy.allows(HostProtocol.Method.updateStatus, with: .standard))
        #expect(LinkMethodPolicy.allows(HostProtocol.Method.setSessionTitle, with: .standard))
        #expect(!LinkMethodPolicy.allows(HostProtocol.Method.configureTitles, with: .standard))
        #expect(LinkMethodPolicy.allows(HostProtocol.Method.configureTitles, with: LinkGrants(manageHost: true)))
        #expect(
            !LinkMethodPolicy.allows(
                HostProtocol.Method.updateReport, with: LinkGrants(managePlugins: true, manageHost: true)))
    }

    @Test func grantsChosenOnTheMacReachTheHost() async throws {
        let harness = try GatewayHarness()
        let (host, _) = try await harness.pairDevice(grants: LinkGrants(managePlugins: true))
        #expect(host.grants.managePlugins)
        #expect(harness.admitted.withLock { $0.first?.1.managePlugins } == true)
    }

    @Test func aUsedSecretNeverPairsAgain() async throws {
        let harness = try GatewayHarness()
        let invite = try #require(await harness.gateway.openPairingWindow().pairing?.invite)
        async let answer: Void = harness.answerNextRequest(accept: true)
        _ = try await LinkInitiator.pair(
            over: try harness.connection(), identity: LinkIdentity(), credential: .invite(invite),
            device: harness.device,
            awaitingConfirmation: { _ in })
        await answer

        await #expect(throws: LinkError.refused(.noPairingWindow)) {
            _ = try await LinkInitiator.pair(
                over: try harness.connection(), identity: LinkIdentity(), credential: .invite(invite),
                device: harness.device, awaitingConfirmation: { _ in })
        }
    }

    @Test func anExpiredWindowRefuses() async throws {
        let harness = try GatewayHarness()
        let invite = try #require(await harness.gateway.openPairingWindow().pairing?.invite)
        harness.advance(by: 301)
        await #expect(throws: LinkError.refused(.noPairingWindow)) {
            _ = try await LinkInitiator.pair(
                over: try harness.connection(), identity: LinkIdentity(), credential: .invite(invite),
                device: harness.device, awaitingConfirmation: { _ in })
        }
    }

    @Test func threeWrongCodesCloseTheWindow() async throws {
        let harness = try GatewayHarness()
        await harness.gateway.openPairingWindow()
        var refusals: [LinkError] = []
        for _ in 0..<4 {
            do {
                _ = try await LinkInitiator.pair(
                    over: try harness.connection(), identity: LinkIdentity(),
                    credential: .code(try require(PairingCode(typed: "ZZZZZZ"))),
                    device: harness.device, awaitingConfirmation: { _ in })
            } catch let error as LinkError {
                refusals.append(error)
            }
        }
        #expect(
            refusals == [
                .refused(.wrongCode), .refused(.wrongCode), .refused(.tooManyAttempts), .refused(.tooManyAttempts),
            ])
        #expect(await harness.gateway.status.pairing?.phase == .tooManyAttempts)
    }

    @Test func pairingByCodeShowsTheSameVerificationOnBothScreens() async throws {
        let harness = try GatewayHarness()
        let status = await harness.gateway.openPairingWindow()
        let code = try require(PairingCode(typed: try require(status.pairing?.code).lowercased()))
        let shown = VerificationBox(nil)
        async let answer: Void = harness.answerNextRequest(accept: true)
        let (_, result) = try await LinkInitiator.pair(
            over: try harness.connection(), identity: LinkIdentity(), credential: .code(code), device: harness.device,
            awaitingConfirmation: { code in shown.withLock { $0 = code } })
        await answer
        #expect(result.hostKey == status.hostKey)
        let request = try #require(await harness.gateway.status.pairing?.request)
        #expect(request.usedCode)
        #expect(shown.value == request.verification)
    }

    @Test func theMacCanDecline() async throws {
        let harness = try GatewayHarness()
        let invite = try #require(await harness.gateway.openPairingWindow().pairing?.invite)
        async let answer: Void = harness.answerNextRequest(accept: false)
        await #expect(throws: LinkError.rejected) {
            _ = try await LinkInitiator.pair(
                over: try harness.connection(), identity: LinkIdentity(), credential: .invite(invite),
                device: harness.device, awaitingConfirmation: { _ in })
        }
        await answer
        #expect(await harness.gateway.status.activeDevices.isEmpty)
    }

    @Test func aHostWithTheWrongKeyIsNeverTrusted() async throws {
        let harness = try GatewayHarness()
        var invite = try #require(await harness.gateway.openPairingWindow().pairing?.invite)
        invite.hostKey = LinkIdentity().publicKey
        await #expect(throws: LinkError.hostKeyMismatch) {
            _ = try await LinkInitiator.pair(
                over: try harness.connection(), identity: LinkIdentity(), credential: .invite(invite),
                device: harness.device, awaitingConfirmation: { _ in })
        }
        // The device stopped before proving anything, so the window is still good.
        #expect(await harness.gateway.status.pairing?.phase == .open)
    }

    @Test func anUnpairedKeyIsTurnedAway() async throws {
        let harness = try GatewayHarness()
        let (host, _) = try await harness.pairDevice()
        var stranger = host
        stranger.deviceKey = LinkIdentity().rawRepresentation
        await #expect(throws: LinkError.unknownDevice) { _ = try await harness.connect(stranger) }
    }

    @Test func aRevokedDeviceIsCutOffAndRefused() async throws {
        let harness = try GatewayHarness()
        let (host, live) = try await harness.pairDevice()
        let deviceID = try #require(await harness.gateway.status.activeDevices.first?.id)
        var incoming = live.incoming().makeAsyncIterator()

        await harness.gateway.revoke(deviceID)
        #expect(await incoming.next() == nil, "the live connection closes")
        await #expect(throws: LinkError.revoked) { _ = try await harness.connect(host) }
        #expect(await harness.gateway.status.activeDevices.isEmpty)

        // Undo.
        await harness.gateway.restore(deviceID)
        _ = try await harness.connect(host)
    }

    @Test func anOrganizationPolicyTurnsDevicesAwayWithoutForgettingThem() async throws {
        let harness = try GatewayHarness()
        let (host, _) = try await harness.pairDevice()
        await harness.gateway.setAllowedByPolicy(false)
        await #expect(throws: LinkError.disabledByPolicy) { _ = try await harness.connect(host) }
        #expect(await harness.gateway.openPairingWindow().pairing == nil)
        #expect(await harness.gateway.status.activeDevices.count == 1)
        await harness.gateway.setAllowedByPolicy(true)
        _ = try await harness.connect(host)
    }

    @Test func theSameInstallationPairingAgainReplacesItsEntry() async throws {
        let harness = try GatewayHarness()
        let secret = Data(repeating: 9, count: 32)
        for _ in 0..<2 {
            let invite = try #require(await harness.gateway.openPairingWindow().pairing?.invite)
            async let answer: Void = harness.answerNextRequest(accept: true)
            _ = try await LinkInitiator.pair(
                over: try harness.connection(), identity: LinkIdentity(), credential: .invite(invite),
                device: harness.device, installationSecret: secret, awaitingConfirmation: { _ in })
            await answer
        }
        #expect(await harness.gateway.status.activeDevices.count == 1)
    }

    @Test func pairedDevicesSurviveARestart() async throws {
        let harness = try GatewayHarness()
        let (host, _) = try await harness.pairDevice()
        let deviceID = try #require(await harness.gateway.status.activeDevices.first?.id)
        await harness.gateway.rename(deviceID, to: "  Phone  ")
        let registry = LinkDeviceRegistry.load(from: harness.gateway.configuration.registryURL)
        #expect(registry.isEnabled)
        #expect(registry.devices.map(\.name) == ["Phone"])
        #expect(registry.device(withKey: try host.identity().publicKey)?.id == deviceID)
    }
}

/// Holds what a `@Sendable` callback saw.
typealias VerificationBox = LinkLocked<VerificationCode?>
