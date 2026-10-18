import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import Testing

@testable import NativeHost

@Suite("Plugins on the host", .serialized, .timeLimit(.minutes(1)))
struct PluginTests {
    /// Installs a plugin folder with a manifest and an asset.
    private func install(
        _ id: String, in harness: HostHarness, enabledByDefault: Bool? = nil, asset: Data = Data("mark".utf8)
    ) throws {
        let folder = harness.plugins.appending(path: id, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder.appending(path: "art"), withIntermediateDirectories: true)
        var manifest: [String: Any] = ["id": id, "name": "Plugin \(id)", "version": "1.0", "themes": [["id": "dusk"]]]
        manifest["enabledByDefault"] = enabledByDefault
        try JSONSerialization.data(withJSONObject: manifest).write(to: folder.appending(path: "plugin.json"))
        try asset.write(to: folder.appending(path: "art/mark.png"))
    }

    @Test("Clients get every installed plugin with its manifest, and on/off choices survive a restart")
    func catalog() async throws {
        let harness = try HostHarness()
        try install("aurora", in: harness)
        try install("labs", in: harness, enabledByDefault: false)
        try harness.start()
        let first = try await harness.connect()
        let plugins = try await first.client.plugins()
        #expect(plugins.map(\.id) == ["aurora", "labs"])
        #expect(plugins.map(\.isEnabled) == [true, false])
        #expect(plugins.first?.manifest["themes"] == .array([.object(["id": .string("dusk")])]))

        let watcher = try await harness.connect()
        _ = try await first.client.setPluginEnabled("aurora", false)
        try await watcher.wait("the change to reach the other client") {
            await $0.lastPlugins?.first?.isEnabled == false
        }
        await first.stop()
        await watcher.stop()

        harness.kill()
        try harness.start()
        let again = try await harness.connect()
        #expect(try await again.client.plugins().map(\.isEnabled) == [false, false])
        await again.stop()
    }

    @Test("Assets come with their hash, and a current copy isn't sent again")
    func assets() async throws {
        let harness = try HostHarness()
        try install("aurora", in: harness, asset: Data("pixels".utf8))
        try harness.start()
        let recorder = try await harness.connect()
        let asset = try await recorder.client.pluginAsset(PluginAssetParams(pluginID: "aurora", path: "art/mark.png"))
        #expect(asset.data == Data("pixels".utf8))
        #expect(asset.hash == ContentHash.sha256(Data("pixels".utf8)))
        let again = try await recorder.client.pluginAsset(
            PluginAssetParams(pluginID: "aurora", path: "art/mark.png", knownHash: asset.hash))
        #expect(again.data == nil)
        await recorder.stop()
    }

    @Test(
        "Asset paths can't leave the plugin's folder",
        arguments: ["../aurora-secret.txt", "/etc/hosts", "art/../../aurora-secret.txt", "escape/hosts"])
    func confinement(path: String) async throws {
        let harness = try HostHarness()
        try install("aurora", in: harness)
        try Data("secret".utf8).write(to: harness.plugins.appending(path: "aurora-secret.txt"))
        // A link inside the folder that points outside it.
        try FileManager.default.createSymbolicLink(
            at: harness.plugins.appending(path: "aurora/escape"), withDestinationURL: URL(filePath: "/etc"))
        try harness.start()
        let recorder = try await harness.connect()
        await #expect(throws: RPCError.self) {
            _ = try await recorder.client.pluginAsset(PluginAssetParams(pluginID: "aurora", path: path))
        }
        await recorder.stop()
    }

    @Test("Assets over the size limit are refused")
    func sizeLimit() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "plugins-\(UUID().uuidString.prefix(8))")
        let folder = root.appending(path: "big")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"{"id":"big","name":"Big"}"#.utf8).write(to: folder.appending(path: "plugin.json"))
        try Data(count: PluginAsset.sizeLimit + 1).write(to: folder.appending(path: "huge.bin"))
        #expect(throws: PluginCatalog.Failure.self) {
            _ = try PluginCatalog(directory: root).asset(pluginID: "big", path: "huge.bin")
        }
        try FileManager.default.removeItem(at: root)
    }

    @Test("Cached assets are there when the host isn't")
    func offlineCache() async throws {
        let harness = try HostHarness()
        try install("aurora", in: harness, asset: Data("cached".utf8))
        try harness.start()
        let recorder = try await harness.connect()
        let assets = PluginAssets(client: recorder.client, directory: harness.root.appending(path: "asset-cache"))
        #expect(try await assets.data(pluginID: "aurora", path: "art/mark.png") == Data("cached".utf8))
        harness.kill()
        try await recorder.wait("the client to notice") { await $0.client.hostInfo == nil }
        #expect(try await assets.data(pluginID: "aurora", path: "art/mark.png") == Data("cached".utf8))
        await recorder.stop()
    }

    @Test("A paired device without the grant can't turn plugins on or off")
    @HostActor
    func grants() async throws {
        let harness = try HostHarness()
        try install("aurora", in: harness)
        let configuration = HostCore.Configuration(
            location: harness.location, hostInfo: PeerInfo(name: "test", version: "1", build: "1"), machineName: "test",
            bootTime: nil, environment: { [:] }, pluginsDirectory: harness.plugins, exit: { _ in })
        let core = try HostCore(configuration: configuration)
        let transport = InProcessTransport { stream in
            await core.accept(stream, grants: ClientGrants(managePlugins: false))
        }
        let client = NativeHostClient(
            transport: transport, clientInfo: PeerInfo(name: "phone", version: "1", build: "1"))
        await client.start()
        _ = try await client.connected()
        #expect(try await client.plugins().map(\.id) == ["aurora"])
        await #expect(throws: RPCError.self) {
            _ = try await client.setPluginEnabled("aurora", false)
        }
        await client.stop()
    }
}

/// Connects a client straight to an in-process host, as a paired transport would after its handshake.
private struct InProcessTransport: HostTransport {
    let accept: @Sendable (any ByteStream) async -> Void

    var displayName: String { "In process" }

    func connect() async throws -> any ByteStream {
        let (clientEnd, hostEnd) = try UnixSocket.pair()
        await accept(ByteChannel.socket(hostEnd, label: "host"))
        return ByteChannel.socket(clientEnd, label: "client")
    }
}
