import ACP
import Foundation
import NativeHostProtocol
import Synchronization
import Testing

@testable import NativeHost
@testable import NativeHostClient

#if os(macOS)
import NativeHostMac
#endif

@Suite("Files on a host", .timeLimit(.minutes(1)))
struct HostFilesTests {
    @Test("Reads return whole files, ranges of them and binary data as it is")
    func reading() async throws {
        let host = try await FilesHost.make()
        let files = RemoteFiles(client: host.owner)
        let text = host.project.appending(path: "notes.txt")
        try Data("hello, world".utf8).write(to: text)
        let binary = host.project.appending(path: "bytes.bin")
        let bytes = Data((0...255).map(UInt8.init) + (0...255).reversed().map(UInt8.init))
        try bytes.write(to: binary)

        let whole = try await files.read(plainPath(text))
        #expect(whole.data == Data("hello, world".utf8))
        #expect(whole.size == 12)
        #expect(whole.modifiedAt != nil)
        #expect(
            try await files.read(plainPath(text), range: FileByteRange(offset: 7, length: 5)).data == Data("world".utf8)
        )
        // Past the end reads what's there; from beyond it, nothing.
        let tail = try await files.read(plainPath(text), range: FileByteRange(offset: 10, length: 100))
        #expect(tail.data == Data("ld".utf8))
        #expect(tail.size == 12)
        #expect(try await files.read(plainPath(text), range: FileByteRange(offset: 50, length: 4)).data.isEmpty)
        #expect(try await files.data(at: plainPath(binary)) == bytes)
        #expect(
            try await files.read(plainPath(binary), range: FileByteRange(offset: 254, length: 4)).data
                == Data([254, 255, 255, 254]))
        await host.stop()
    }

    @Test("A file bigger than one answer is refused whole, and read in pieces up to the caller's limit")
    func sizeLimit() async throws {
        let host = try await FilesHost.make()
        let files = RemoteFiles(client: host.owner)
        let big = host.project.appending(path: "big.bin")
        let size = FileReadResult.sizeLimit * 5 / 2
        // A pattern whose length doesn't divide a piece's, so a piece read from the wrong place shows.
        let pattern = Data((0..<251).map(UInt8.init))
        var contents = Data(capacity: size + pattern.count)
        while contents.count < size { contents.append(pattern) }
        contents = contents.prefix(size)
        try contents.write(to: big)

        await #expect(throws: HostFileError.tooLarge(path: plainPath(big), size: size, limit: FileReadResult.sizeLimit))
        {
            try await files.read(plainPath(big))
        }
        let tooLong = await #expect(throws: RPCError.self) {
            try await files.read(plainPath(big), range: FileByteRange(offset: 0, length: FileReadResult.sizeLimit + 1))
        }
        #expect(tooLong?.code == -32602)
        #expect(try await files.data(at: plainPath(big)) == contents)
        await #expect(throws: HostFileError.tooLarge(path: plainPath(big), size: size, limit: size - 1)) {
            try await files.data(at: plainPath(big), limit: size - 1)
        }
        await host.stop()
    }

    @Test("Folders list their entries, links as links, and stat follows links inside the project")
    func listAndStat() async throws {
        let host = try await FilesHost.make()
        let files = RemoteFiles(client: host.owner)
        let manager = FileManager.default
        try Data("abc".utf8).write(to: host.project.appending(path: "b.txt"))
        try manager.createDirectory(at: host.project.appending(path: "a-folder"), withIntermediateDirectories: true)
        try manager.createSymbolicLink(
            atPath: plainPath(host.project.appending(path: "c-link")), withDestinationPath: "b.txt")

        let listing = try await files.entries(in: host.projectPath)
        #expect(listing.entries.map(\.name) == ["a-folder", "b.txt", "c-link"])
        #expect(listing.entries.map(\.kind) == [.directory, .file, .symlink])
        #expect(listing.entries[1].size == 3)
        #expect(!listing.isTruncated)

        let linked = try #require(try await files.info(at: plainPath(host.project.appending(path: "c-link"))))
        #expect(linked.kind == .file)
        #expect(linked.size == 3)
        #expect(linked.path.hasSuffix("/project/b.txt"))
        #expect(try await files.info(at: host.projectPath)?.kind == .directory)
        #expect(try await files.info(at: plainPath(host.project.appending(path: "missing.txt"))) == nil)

        let file = plainPath(host.project.appending(path: "b.txt"))
        await #expect(throws: HostFileError.notADirectory(path: file)) { try await files.entries(in: file) }
        await #expect(throws: HostFileError.notAFile(path: host.projectPath)) { try await files.read(host.projectPath) }
        let missing = plainPath(host.project.appending(path: "missing.txt"))
        await #expect(throws: HostFileError.notFound(path: missing)) { try await files.read(missing) }
        await host.stop()
    }

    /// Ways out of the project: `..`, links to a folder or a file outside it, and absolute paths elsewhere.
    enum Escape: CaseIterable {
        case dotDot, linkedFolder, linkedFile, elsewhere

        func file(in host: FilesHost) -> String {
            switch self {
            case .dotDot: host.projectPath + "/../outside/secret.txt"
            case .linkedFolder: host.projectPath + "/out/secret.txt"
            case .linkedFile: host.projectPath + "/secret-link"
            case .elsewhere: "/etc/hosts"
            }
        }

        func folder(in host: FilesHost) -> String {
            switch self {
            case .dotDot: host.projectPath + "/../outside"
            case .linkedFolder, .linkedFile: host.projectPath + "/out"
            case .elsewhere: "/etc"
            }
        }
    }

    @Test("Paths that resolve outside the host's projects are refused", arguments: Escape.allCases)
    func escapes(_ escape: Escape) async throws {
        let host = try await FilesHost.make()
        let files = RemoteFiles(client: host.owner)
        let secret = host.outside.appending(path: "secret.txt")
        try Data("secret".utf8).write(to: secret)
        try FileManager.default.createSymbolicLink(
            atPath: host.projectPath + "/out", withDestinationPath: plainPath(host.outside))
        try FileManager.default.createSymbolicLink(
            atPath: host.projectPath + "/secret-link", withDestinationPath: plainPath(secret))

        let (file, folder) = (escape.file(in: host), escape.folder(in: host))
        try await expectRefusal(.outsideProjects) { try await files.read(file) }
        try await expectRefusal(.outsideProjects) { try await files.info(at: file) }
        try await expectRefusal(.outsideProjects) { try await files.entries(in: folder) }
        try await expectRefusal(.outsideProjects) { try await host.owner.watchFiles(FileWatchParams(root: folder)) }
        await host.stop()
    }

    @Test("Relative paths mean nothing on a host")
    func relativePaths() async throws {
        let host = try await FilesHost.make()
        let refusal = await #expect(throws: RPCError.self) {
            try await RemoteFiles(client: host.owner).read("notes.txt")
        }
        #expect(refusal?.code == -32602)
        await host.stop()
    }

    @Test("A client without the runCommands grant can't read, list, stat or watch")
    func grant() async throws {
        let host = try await FilesHost.make()
        try Data("hi".utf8).write(to: host.project.appending(path: "notes.txt"))
        let device = try await host.connect(ClientGrants(managePlugins: true, manageHost: true, isLocal: false))
        let files = RemoteFiles(client: device)
        let file = host.projectPath + "/notes.txt"
        try await expectRefusal(.notAuthorized) { try await files.read(file) }
        try await expectRefusal(.notAuthorized) { try await files.info(at: file) }
        try await expectRefusal(.notAuthorized) { try await files.entries(in: host.projectPath) }
        try await expectRefusal(.notAuthorized) { try await device.watchFiles(FileWatchParams(root: host.projectPath)) }
        #expect(await host.watchCount() == 0)
        await device.stop()
        await host.stop()
    }

    @Test("Watched changes arrive relative to the folder as the client spelled it, coalesced, until it stops")
    func watching() async throws {
        let watcher = ScriptedFileWatching()
        let host = try await FilesHost.make(watching: watcher)
        let heard = Recorded<RemoteFileChange>()
        let following = Task {
            for await change in RemoteFiles(client: host.owner).changes(under: host.projectPath + "/") {
                heard.append(change)
            }
        }
        let root = try await watcher.root()
        #expect(root == ProjectPaths.resolvedPath(host.projectPath))

        watcher.send(FileWatchBatch(paths: [root + "/src/b.swift", root, root + "/a.txt"]))
        try await pollUntil("the first change") { heard.values.count == 1 }
        #expect(
            heard.values[0]
                == RemoteFileChange(
                    paths: [host.projectPath, "\(host.projectPath)/a.txt", "\(host.projectPath)/src/b.swift"],
                    isOverflow: false))

        // Right after a batch, more changes wait for the rest of the window and come together.
        watcher.send(FileWatchBatch(paths: [root + "/c.txt"]))
        watcher.send(FileWatchBatch(paths: [root + "/d.txt", root + "/c.txt"]))
        try await pollUntil("the next changes") { Set(heard.values.dropFirst().flatMap(\.paths)).count == 2 }
        #expect(
            Set(heard.values.dropFirst().flatMap(\.paths)) == [
                "\(host.projectPath)/c.txt", "\(host.projectPath)/d.txt",
            ])

        // Lost track, or something outside the folder: look again at everything.
        let before = heard.values.count
        watcher.send(FileWatchBatch(paths: ["/elsewhere/x"]))
        try await pollUntil("an overflow") { heard.values.dropFirst(before).contains(where: \.isOverflow) }
        let overflows = heard.values.count
        watcher.send(FileWatchBatch(paths: [], isOverflow: true))
        try await pollUntil("another overflow") { heard.values.dropFirst(overflows).contains(where: \.isOverflow) }

        // Stopping iterating unwatches it on the host.
        following.cancel()
        try await pollUntil("the host to stop watching") { watcher.activeCount == 0 }
        #expect(await host.watchCount() == 0)
        await host.stop()
    }

    @Test("A client's watches stop when it goes away")
    func cleanupOnDisconnect() async throws {
        let watcher = ScriptedFileWatching()
        let host = try await FilesHost.make(watching: watcher)
        let device = try await host.connect(
            ClientGrants(managePlugins: false, manageHost: false, isLocal: false, runCommands: true))
        try await device.watchFiles(FileWatchParams(root: host.projectPath))
        try await device.watchFiles(FileWatchParams(root: host.projectPath))
        #expect(watcher.activeCount == 2)
        #expect(await host.watchCount() == 2)
        await device.stop()
        try await pollUntil("the host to stop watching") { watcher.activeCount == 0 }
        #expect(await host.watchCount() == 0)
        await host.stop()
    }

    /// The watcher a host on this platform uses.
    private static var platformWatching: any FileWatching {
        #if os(macOS)
        FSEventsFileWatching(latency: 0.05)
        #else
        PollingFileWatching(interval: .milliseconds(100))
        #endif
    }

    @Test("End to end over the local socket: read, list, stat and watch, across a dropped connection")
    func overTheSocket() async throws {
        let harness = try HostHarness()
        let project = harness.root.appending(path: "project", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let configuration = HostCore.Configuration(
            location: harness.location, hostInfo: PeerInfo(name: "test", version: "1", build: "1"), machineName: "test",
            bootTime: nil, environment: { [:] }, pluginsDirectory: harness.plugins, exit: { _ in },
            fileWatching: Self.platformWatching)
        let core = try await HostMain.start(configuration, verifier: nil)
        let transport = CuttableTransport(location: harness.location)
        let client = NativeHostClient(
            transport: transport, clientInfo: PeerInfo(name: "laptop", version: "1", build: "1"))
        await client.start()
        _ = try await client.connected()
        _ = try await client.addProject(plainPath(project))
        let files = RemoteFiles(client: client)
        try Data("# Read me".utf8).write(to: project.appending(path: "README.md"))

        #expect(try await files.data(at: plainPath(project) + "/README.md") == Data("# Read me".utf8))
        #expect(try await files.entries(in: plainPath(project)).entries.map(\.name) == ["README.md"])
        #expect(try await files.info(at: plainPath(project) + "/README.md")?.size == 9)

        let heard = Recorded<RemoteFileChange>()
        let following = Task {
            for await change in files.changes(under: plainPath(project)) {
                heard.append(change)
            }
        }
        // The host counts a watch once its watcher is running.
        try await pollUntil("the watch to start") { await FilesHost.watchCount(core) == 1 }
        try Data("new".utf8).write(to: project.appending(path: "new.txt"))
        try await pollUntil("the new file") { heard.values.flatMap(\.paths).contains(plainPath(project) + "/new.txt") }

        // A dropped connection loses the host's watch; the client watches again and says to rescan,
        // once the new watch is running.
        transport.cut()
        try await pollUntil("an overflow after reconnecting") { heard.values.contains(where: \.isOverflow) }
        try Data("after".utf8).write(to: project.appending(path: "after.txt"))
        try await pollUntil("a change after reconnecting") {
            heard.values.flatMap(\.paths).contains(plainPath(project) + "/after.txt")
        }
        #expect(await FilesHost.watchCount(core) == 1)

        following.cancel()
        try await pollUntil("the unwatch") { await FilesHost.watchCount(core) == 0 }
        await client.stop()
        withExtendedLifetime(core) {}
    }
}

/// Fails unless `body` throws the host error `code`.
private func expectRefusal(
    _ code: HostErrorCode, sourceLocation: SourceLocation = #_sourceLocation, _ body: () async throws -> some Any
) async throws {
    do {
        _ = try await body()
        Issue.record("Expected \(code), but it went through", sourceLocation: sourceLocation)
    } catch {
        #expect(HostErrorCode(error) == code, "\(error)", sourceLocation: sourceLocation)
    }
}
