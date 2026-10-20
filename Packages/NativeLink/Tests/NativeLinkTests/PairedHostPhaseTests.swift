import Foundation
import NativeHostClient
import NativeHostProtocol
import Testing

@testable import NativeLink

/// What a client shows for a paired host's connection.
@Suite struct PairedHostPhaseTests {
    @Test func followsTheClientAndSaysWhenItsOffline() {
        let info = HostInfo(
            protocolVersion: HostProtocol.version, hostID: HostID(), machineName: "mini",
            hostInfo: PeerInfo(name: "Native Host", version: "1.4", build: "140"), epoch: UUID(), processID: 1,
            startedAt: .now, channel: "")
        #expect(PairedHostPhase(.connected(info)).hostInfo == info)
        #expect(PairedHostPhase(.connected(info)).isConnected)
        #expect(!PairedHostPhase(.connecting).isOffline)
        #expect(!PairedHostPhase(.reconnecting(attempt: 2, reason: "Wi-Fi")).isOffline, "a blip isn't offline")
        #expect(PairedHostPhase(.unreachable(reason: "No route")).isOffline)
        #expect(PairedHostPhase.pairingEnded(.revoked).isOffline)
        #expect(PairedHostPhase.pairingEnded(.revoked).hostInfo == nil)
    }
}
