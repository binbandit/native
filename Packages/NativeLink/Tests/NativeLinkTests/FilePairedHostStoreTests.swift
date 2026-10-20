import Foundation
import NativeHostProtocol
import Testing

@testable import NativeLink

/// How a Mac keeps its paired hosts: a file per host, readable by the user alone.
@Suite struct FilePairedHostStoreTests {
    private let directory = URL(filePath: "/tmp/nl-store-\(UUID().uuidString.prefix(8))/Hosts")

    private func pairedHost(named name: String, at date: Date) -> PairedHost {
        let result = LinkPairingResult(
            hostID: HostID(), hostKey: LinkIdentity().publicKey, hostName: name, deviceID: UUID(),
            grants: LinkGrants(manageHost: true, runCommands: true),
            addresses: [LinkAddress(kind: .loopback, host: "127.0.0.1", port: 47_118)])
        return PairedHost(result: result, identity: LinkIdentity(), pairedAt: date)
    }

    @Test func keepsEachPairingInItsOwnPrivateFile() throws {
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        let store = FilePairedHostStore(directory: directory)
        #expect(try store.hosts().isEmpty, "nothing paired before the folder exists")

        let mini = pairedHost(named: "mini", at: Date(timeIntervalSince1970: 1_800_000_000))
        let studio = pairedHost(named: "studio", at: Date(timeIntervalSince1970: 1_800_000_100))
        try store.save(studio)
        try store.save(mini)
        let hosts = try store.hosts()
        #expect(hosts.map(\.machineName) == ["mini", "studio"], "in the order they were paired")
        #expect(hosts.first?.deviceKey == mini.deviceKey)
        #expect(try hosts.first?.identity().publicKey == mini.identity().publicKey)
        #expect(hosts.first?.grants.runCommands == true)

        let folder = try FileManager.default.attributesOfItem(atPath: directory.path(percentEncoded: false))
        #expect((folder[.posixPermissions] as? Int) == 0o700)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
        #expect(files.count == 2, "no staging files left behind")
        for file in files {
            let attributes = try FileManager.default.attributesOfItem(
                atPath: directory.appending(path: file).path(percentEncoded: false))
            #expect((attributes[.posixPermissions] as? Int) == 0o600)
        }
    }

    @Test func renamingReplacesAndRemovingTouchesOnlyThatHost() throws {
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        let store = FilePairedHostStore(directory: directory)
        var mini = pairedHost(named: "mini", at: .now)
        let studio = pairedHost(named: "studio", at: .now.addingTimeInterval(1))
        try store.save(mini)
        try store.save(studio)
        mini.label = "Closet mini"
        try store.save(mini)
        #expect(try store.hosts().map(\.displayName) == ["Closet mini", "studio"])

        try store.remove(mini.hostID)
        try store.remove(mini.hostID)
        #expect(try store.hosts().map(\.hostID) == [studio.hostID])
    }

    @Test func skipsFilesItCantRead() throws {
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        let store = FilePairedHostStore(directory: directory)
        try store.save(pairedHost(named: "mini", at: .now))
        try Data("not a pairing".utf8).write(to: directory.appending(path: "broken.json"))
        #expect(try store.hosts().map(\.machineName) == ["mini"])
    }
}
