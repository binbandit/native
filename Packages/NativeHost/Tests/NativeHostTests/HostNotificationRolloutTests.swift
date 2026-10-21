import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import Testing

@MainActor
@Suite("Host notification rollout", .serialized, .timeLimit(.minutes(1)))
struct HostNotificationRolloutTests {
    @Test("A protocol-v2 host without notification methods keeps session notifications and the journal")
    func olderHostKeepsFallback() async throws {
        let name = "native-notification-rollout-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let client = NativeHostClient(
            transport: LegacyNotificationHost(), clientInfo: PeerInfo(name: "tests", version: "1", build: "1"))
        await client.start()
        let info = try await client.connected()
        #expect(info.protocolVersion == HostProtocol.version)
        #expect(info.notificationEvents == nil)
        await #expect(throws: RPCError.self) { try await client.notifications() }

        // A host can also have been downgraded after this client already followed notifications.
        defaults.set([info.hostID.description: Int64(12)], forKey: HostNotificationHistory.defaultsKey)
        let history = HostNotificationHistory(defaults: defaults)
        #expect(!history.usesHostNotifications(on: info, enabled: true))
        #expect(history.usesActivitySummary(on: info, enabled: true))
        await client.stop()
    }

    @Test("The first enabled launch preserves finished work even when notification catch-up wins the race")
    func upgradeKeepsAwaySummary() async throws {
        let name = "native-notification-rollout-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let harness = try HostHarness()
        try harness.start()
        let before = try await harness.connect()
        let activityCursor = try await before.client.activity().last?.id ?? 0
        let session = try await before.client.newSession(
            NewSessionParams(agentID: "fake", cwd: harness.root.path(percentEncoded: false), attach: true)
        ).id
        _ = try await before.client.prompt(PromptParams(sessionID: session, text: "slow 3"))
        await before.stop()
        try await Task.sleep(for: .seconds(2))

        let after = try await harness.connect()
        let info = try #require(await after.client.hostInfo)
        #expect(info.notificationEvents == true)
        let history = HostNotificationHistory(defaults: defaults)
        #expect(history.lastSeen(on: info.hostID) == nil)
        let list = try await after.client.notifications()
        history.remember(try #require(list.latestID), on: info.hostID)

        let entries = try await after.client.activity(after: activityCursor)
        let sessions = try await after.client.sessions()
        let summary =
            history.usesActivitySummary(on: info, enabled: true)
            ? AwaySummary(entries: entries, sessions: sessions) : nil
        #expect(summary?.items.map(\.id) == [session])
        #expect(summary?.headline == "1 task finished.")

        // The bridge lasts one launch, not every reconnection or every subsequent launch.
        let nextLaunch = HostNotificationHistory(defaults: defaults)
        #expect(!nextLaunch.usesActivitySummary(on: info, enabled: true))
        #expect(nextLaunch.usesActivitySummary(on: info, enabled: false))
        let nextList = try await after.client.notifications(after: nextLaunch.lastSeen(on: info.hostID))
        #expect(nextList.notifications.isEmpty)
        await after.stop()
    }

    @Test("A new host's empty baseline survives relaunch and cursors never move backwards")
    func emptyBaseline() throws {
        let name = "native-notification-rollout-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let host = HostID()
        let history = HostNotificationHistory(defaults: defaults)
        #expect(history.lastSeen(on: host) == nil)
        history.remember(0, on: host)
        let next = HostNotificationHistory(defaults: defaults)
        #expect(next.lastSeen(on: host) == 0)
        next.remember(4, on: host)
        next.remember(2, on: host)
        #expect(HostNotificationHistory(defaults: defaults).lastSeen(on: host) == 4)
    }
}

/// The protocol-v2 handshake predates notifications. Unknown methods still return normal RPC errors.
private final class LegacyNotificationHost: HostTransport {
    var displayName: String { "Legacy host" }

    func connect() async throws -> any ByteStream {
        let (clientEnd, hostEnd) = try UnixSocket.pair()
        let box = LegacyNotificationPeer()
        let peer = JSONRPCPeer(channel: ByteChannel.socket(hostEnd, label: "legacy-host"), label: "legacy-host") {
            event in
            guard case .request(let message) = event, let id = message.id, let peer = await box.peer else { return }
            if message.method == HostProtocol.Method.initialize {
                try? peer.respond(
                    to: id,
                    with: HostInfo(
                        protocolVersion: HostProtocol.version, hostID: HostID(), machineName: "Legacy host",
                        hostInfo: PeerInfo(name: "Native Host", version: "0.9", build: "1"), epoch: UUID(),
                        processID: 1, startedAt: .now, channel: "tests"))
            } else {
                try? peer.respond(to: id, error: .methodNotFound(message.method))
            }
        }
        await box.set(peer)
        peer.start()
        return ByteChannel.socket(clientEnd, label: "legacy-client")
    }
}

private actor LegacyNotificationPeer {
    var peer: JSONRPCPeer?
    func set(_ peer: JSONRPCPeer) { self.peer = peer }
}
