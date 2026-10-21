import Foundation
import NativeHostProtocol
import Testing

@testable import NativeLink

/// `"Native Host" pair` against a gateway serving its control socket, as on a host without a screen.
@Suite struct PairCommandTests {
    let build = PeerInfo(name: "Native Host", version: "1.4.0", build: "140")

    @Test func printsALinkThenSaysWhoPaired() async throws {
        let host = try await ControlledGateway.start()
        let run = host.run(LinkPairCommand.Options(grants: LinkGrants(runCommands: true), printsJSON: true))
        let invite = try await run.invite()
        #expect(invite.grants == LinkGrants(runCommands: true))

        let device = LinkDeviceInfo(name: "Laptop", model: "Mac", system: "macOS 27.2")
        let (_, result) = try await LinkInitiator.pair(
            over: try host.connection(), identity: LinkIdentity(), credential: .invite(invite), device: device,
            awaitingConfirmation: { _ in })
        #expect(result.grants == LinkGrants(runCommands: true))
        #expect(await run.exit.value == LinkPairCommand.ExitStatus.paired)

        let events = run.events
        #expect(events.map(\.event) == [.invite, .paired])
        #expect(events.first?.command == LinkPairCommand.marker)
        #expect(events.first?.host == build)
        #expect(events.first?.protocolVersion == HostProtocol.version)
        #expect(events.last?.device?.name == "Laptop")
        #expect(events.last?.grants == LinkGrants(runCommands: true))
        // The window closes with the command, so the link is spent either way.
        try await Task.sleep(for: .milliseconds(200))
        #expect(await host.gateway.status.pairing == nil)
    }

    /// The whole path a Mac takes, over loopback TCP: pair prints a link, Add Host pairs with it
    /// asking for less than it offers, and connects again later as a paired device.
    @Test func aMacPairsOverTCPWithWhatItAsksFor() async throws {
        let hostDirectory = URL(filePath: "/tmp/nl-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: hostDirectory) }
        let gateway = try LinkGateway(
            configuration: .init(
                directory: LinkGateway.Configuration.directory(inHostDirectory: hostDirectory), hostID: HostID(),
                machineName: "Mac mini", includesLoopback: true, preferredPort: 0, advertisesOverBonjour: false),
            keyStore: MemoryKeyStore(), accept: { _, _ in })
        try await gateway.start()
        defer { Task { await gateway.stop() } }
        let lines = LinkLocked<[String]>([])
        let command = LinkPairCommand(
            options: LinkPairCommand.Options(
                grants: LinkGrants(managePlugins: true, manageHost: true, runCommands: true), printsJSON: true),
            hostDirectory: hostDirectory, build: build, output: { line, _ in lines.withLock { $0.append(line) } })
        let exit = Task { await command.run() }
        let run = CommandRun(lines: lines, exit: exit)
        var invite = try await run.invite()
        // The listener comes up with the window; the link lists its port once it's bound.
        invite.addresses = invite.addresses.filter { $0.kind == .loopback }
        #expect(!invite.addresses.isEmpty)

        var mac = LinkDeviceInfo(name: "Laptop", model: "Mac", system: "macOS 27.2")
        mac.requestedGrants = LinkGrants(runCommands: true)
        let (host, channel) = try await LinkPairing.pair(
            credential: .invite(invite), endpoints: LinkPairing.endpoints(for: invite, discovered: []), device: mac,
            log: { _ in }, awaitingConfirmation: { _ in Issue.record("nobody is asked") })
        channel.close()
        #expect(host.grants == LinkGrants(runCommands: true))
        #expect(await exit.value == LinkPairCommand.ExitStatus.paired)

        let stream = try await PairedHostTransport(host: host, device: mac).connect()
        stream.close()
    }

    @Test func givesOnlySessionsUnlessAsked() throws {
        #expect(try LinkPairCommand.parse([]).grants == .standard)
        let options = try LinkPairCommand.parse(["--run-commands", "--install-updates", "--manage-plugins", "--json"])
        #expect(options.grants == LinkGrants(managePlugins: true, manageHost: true, runCommands: true))
        #expect(options.printsJSON)
        #expect(throws: LinkPairCommand.UsageError.self) { try LinkPairCommand.parse(["--everything"]) }
    }

    @Test func saysWhenTheLinkExpires() async throws {
        let host = try await ControlledGateway.start(lifetime: .seconds(1))
        let run = host.run(LinkPairCommand.Options(printsJSON: true))
        #expect(await run.exit.value == LinkPairCommand.ExitStatus.failed)
        #expect(run.events.map(\.event) == [.invite, .failed])
        #expect(run.events.last?.failure == .expired)
    }

    @Test func saysWhenAnotherWindowReplacesIt() async throws {
        let host = try await ControlledGateway.start()
        let run = host.run(LinkPairCommand.Options(printsJSON: true))
        _ = try await run.invite()
        await host.gateway.openPairingWindow()
        #expect(await run.exit.value == LinkPairCommand.ExitStatus.failed)
        #expect(run.events.last?.failure == .replaced)
    }

    @Test func endingNeverClosesAWindowSomebodyElseOpened() async throws {
        let host = try await ControlledGateway.start()
        let run = host.run(LinkPairCommand.Options(printsJSON: true))
        _ = try await run.invite()
        // The Pair iPhone sheet on the host's own screen takes over.
        let sheet = LinkControlClient(hostDirectory: host.hostDirectory)
        await sheet.start()
        for await event in sheet.events {
            if case .status = event { break }
        }
        let opened = try #require(try await sheet.openPairingWindow().pairing?.invite)
        #expect(await run.exit.value == LinkPairCommand.ExitStatus.failed)
        try await Task.sleep(for: .milliseconds(200))
        #expect(await host.gateway.status.pairing?.invite.secret == opened.secret, "the sheet's window stays open")
        await sheet.stop()
        try await Task.sleep(for: .milliseconds(200))
        #expect(await host.gateway.status.pairing == nil, "and closes with the sheet")
    }

    @Test func saysWhenTheHostIsntRunning() async throws {
        let lines = LinkLocked<[String]>([])
        let command = LinkPairCommand(
            options: LinkPairCommand.Options(), hostDirectory: URL(filePath: "/tmp/nl-missing-\(UUID().uuidString)"),
            build: build, output: { line, isError in lines.withLock { $0.append(isError ? "error: \(line)" : line) } })
        #expect(await command.run() == LinkPairCommand.ExitStatus.failed)
        #expect(lines.value.count == 1)
        #expect(lines.value.first?.hasPrefix("error: Native's background host isn't running") == true)
    }

    @Test func talksToPeopleWithoutJSON() async throws {
        let host = try await ControlledGateway.start(lifetime: .seconds(1))
        let run = host.run(LinkPairCommand.Options())
        _ = await run.exit.value
        let text = run.lines.joined(separator: "\n")
        #expect(text.contains("Pairing link for Test Mac"))
        #expect(text.contains("nativecompanion://pair#"))
        #expect(text.contains("can follow and drive tasks."))
        #expect(text.contains("error: The link expired"))
    }
}

/// A gateway serving its control socket, with no network listener: devices connect through socket pairs.
private final class ControlledGateway: Sendable {
    let gateway: LinkGateway
    let hostDirectory: URL

    private init(gateway: LinkGateway, hostDirectory: URL) {
        self.gateway = gateway
        self.hostDirectory = hostDirectory
    }

    static func start(lifetime: Duration = .seconds(300)) async throws -> ControlledGateway {
        // Short: the control socket's path has to fit in sockaddr_un.
        let hostDirectory = URL(filePath: "/tmp/nl-\(UUID().uuidString.prefix(8))")
        let gateway = try LinkGateway(
            configuration: .init(
                directory: LinkGateway.Configuration.directory(inHostDirectory: hostDirectory), hostID: HostID(),
                machineName: "Test Mac", pairingLifetime: lifetime, usesNetwork: false),
            keyStore: MemoryKeyStore(), accept: { _, _ in })
        try await gateway.start()
        return ControlledGateway(gateway: gateway, hostDirectory: hostDirectory)
    }

    deinit {
        let gateway = gateway
        Task { await gateway.stop() }
        try? FileManager.default.removeItem(at: hostDirectory)
    }

    func connection() throws -> any ByteStream {
        let (deviceEnd, hostEnd) = try UnixSocket.pair()
        gateway.serve(ByteChannel.socket(hostEnd, label: "host"))
        return ByteChannel.socket(deviceEnd, label: "device")
    }

    func run(_ options: LinkPairCommand.Options) -> CommandRun {
        let lines = LinkLocked<[String]>([])
        let command = LinkPairCommand(
            options: options, hostDirectory: hostDirectory,
            build: PeerInfo(name: "Native Host", version: "1.4.0", build: "140"),
            output: { line, isError in lines.withLock { $0.append(isError ? "error: \(line)" : line) } })
        return CommandRun(lines: lines, exit: Task { await command.run() })
    }
}

private struct CommandRun {
    let output: LinkLocked<[String]>
    let exit: Task<Int32, Never>

    init(lines: LinkLocked<[String]>, exit: Task<Int32, Never>) {
        output = lines
        self.exit = exit
    }

    var lines: [String] { output.value }
    var events: [LinkPairCommandEvent] { lines.compactMap(LinkPairCommandEvent.init(line:)) }

    /// The link the command printed, once it has.
    func invite() async throws -> PairingInvite {
        let deadline = ContinuousClock.now + .seconds(10)
        while ContinuousClock.now < deadline {
            if let link = events.first(where: { $0.event == .invite })?.link { return try PairingInvite(url: link) }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw MissingValue()
    }
}
