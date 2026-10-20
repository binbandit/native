import Foundation
import NativeHostClient
import NativeHostProtocol
import Synchronization
import Testing

@testable import NativeHost

/// Pairings the gateway reports land in the activity journal, so a pairing nobody confirmed on a
/// screen (`pair` over SSH) still leaves a trace every client sees.
@Suite(.timeLimit(.minutes(1)))
@HostActor
struct DevicePairedJournalTests {
    @Test func aPairingIsJournaledAndSentToClients() async throws {
        let rig = try HostUpdateTests.Rig(HostUpdateEnvironment(provider: .none, current: HostUpdateTests.current))
        let core = rig.core
        let client = NativeHostClient(
            transport: InProcessTransport { stream in await core.accept(stream, grants: .owner) },
            clientInfo: PeerInfo(name: "Native", version: "1", build: "1"))
        let heard = Mutex<[ActivityEntry]>([])
        Task {
            for await event in client.events {
                if case .activity(let entry) = event { heard.withLock { $0.append(entry) } }
            }
        }
        await client.start()
        _ = try await client.connected()

        core.journalDevicePaired("Laptop", detail: "Mac · macOS 27.2. Paired with a link from the pair command.")

        let entry = try #require(try core.store.activity(after: nil, limit: 10).last)
        #expect(entry.kind == .devicePaired)
        #expect(entry.subject == "Laptop")
        #expect(entry.sessionID == nil)
        for _ in 0..<100 where heard.withLock(\.isEmpty) { try await Task.sleep(for: .milliseconds(20)) }
        #expect(heard.withLock { $0.map(\.kind) } == [.devicePaired])
        await client.stop()
    }
}
