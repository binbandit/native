import ACP
import Exec
import Foundation
import NativeHostProtocol
import Synchronization
import Testing

@testable import NativeHost
@testable import NativeHostClient

@Suite("Commands on a host", .timeLimit(.minutes(1)))
struct HostExecTests {
    @Test("A command's exit code, output and input go both ways")
    func roundTrip() async throws {
        let host = try await ExecHost.make()
        let runner = RemoteCommandRunner(client: host.owner)
        let failed = try await runner.run(
            Command("sh", ["-c", "printf out; printf err >&2; exit 3"], in: host.projectPath, environment: [:]))
        #expect(failed.exitCode == 3)
        #expect(failed.output == "out")
        #expect(failed.errorOutput == "err")

        let piped = try await runner.run(
            Command("cat", in: host.projectPath, environment: [:], standardInput: Data("piped\n".utf8)))
        #expect(piped.output == "piped\n")

        // The client's variables go on top of the host's login-shell environment, not instead of it.
        let environment = try await runner.run(
            Command(
                "sh", ["-c", #"printf '%s|%s' "$NATIVE_HOST_ONLY" "$FROM_CLIENT""#], in: host.projectPath,
                environment: ["FROM_CLIENT": "from the client"]))
        #expect(environment.output == "from the host|from the client")

        await #expect(throws: CommandError.notFound("definitely-not-a-command")) {
            try await runner.run(Command("definitely-not-a-command", in: host.projectPath, environment: [:]))
        }
        await host.stop()
    }

    @Test("Output streams as it arrives, and long output arrives whole")
    func streaming() async throws {
        let host = try await ExecHost.make()
        let runner = RemoteCommandRunner(client: host.owner)
        let pieces = Mutex<[(at: ContinuousClock.Instant, text: String)]>([])
        let result = try await runner.run(
            Command("sh", ["-c", "echo one; sleep 1; echo two >&2"], in: host.projectPath, environment: [:])
        ) { output in
            pieces.withLock { $0.append((.now, String(decoding: output.data, as: UTF8.self))) }
        }
        let finished = ContinuousClock.now
        let first = try #require(pieces.withLock { $0.first })
        #expect(first.text == "one\n")
        #expect(finished - first.at > .milliseconds(500), "the first line came only with the answer")
        #expect(result.output == "one\n")
        #expect(result.errorOutput == "two\n")

        // Three times what one answer holds: the host sends it ahead, in order, and nothing is lost.
        let size = 3 * ExecRunResult.inlineLimit + 7
        let script = "head -c \(size) /dev/zero | tr '\\0' x; head -c \(size) /dev/zero | tr '\\0' y >&2"
        for streaming in [false, true] {
            let streamed = Mutex(0)
            let command = Command("sh", ["-c", script], in: host.projectPath, environment: [:])
            let long =
                if streaming {
                    try await runner.run(command) { output in streamed.withLock { $0 += output.data.count } }
                } else {
                    try await runner.run(command)
                }
            #expect(long.standardOutput == Data(repeating: UInt8(ascii: "x"), count: size))
            #expect(long.standardError == Data(repeating: UInt8(ascii: "y"), count: size))
            if streaming {
                #expect(streamed.withLock { $0 } == 2 * size)
            }
        }
        await host.stop()
    }

    @Test("A command past its timeout is stopped")
    func timeout() async throws {
        let host = try await ExecHost.make()
        let runner = RemoteCommandRunner(client: host.owner)
        let started = ContinuousClock.now
        await #expect(throws: CommandError.timedOut("sleep", after: .milliseconds(300))) {
            try await runner.run(
                Command("sleep", ["10"], in: host.projectPath, environment: [:], timeout: .milliseconds(300)))
        }
        #expect(ContinuousClock.now - started < .seconds(5))
        await host.stop()
    }

    @Test("Cancelling the caller stops the command on the host")
    func cancel() async throws {
        let host = try await ExecHost.make()
        let runner = RemoteCommandRunner(client: host.owner)
        let pid = Mutex<pid_t?>(nil)
        let running = Task {
            try await runner.run(
                Command("sh", ["-c", "echo $$; exec sleep 30"], in: host.projectPath, environment: [:])
            ) { output in
                let text = String(decoding: output.data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                pid.withLock { $0 = pid_t(text) }
            }
        }
        let started = try await Self.poll { pid.withLock { $0 } }
        running.cancel()
        await #expect(throws: CancellationError.self) { try await running.value }
        #expect(try await Self.poll { kill(started, 0) == -1 ? true : nil })
        await host.stop()
    }

    @Test("A client that disconnects has its commands stopped")
    func disconnect() async throws {
        let host = try await ExecHost.make()
        let laptop = try await host.connect(ExecHost.commandingDevice, name: "laptop")
        let pid = Mutex<pid_t?>(nil)
        let running = Task {
            try await RemoteCommandRunner(client: laptop).run(
                Command("sh", ["-c", "echo $$; exec sleep 30"], in: host.projectPath, environment: [:])
            ) { output in
                let text = String(decoding: output.data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                pid.withLock { $0 = pid_t(text) }
            }
        }
        let started = try await Self.poll { pid.withLock { $0 } }
        await laptop.stop()
        #expect(try await Self.poll { kill(started, 0) == -1 ? true : nil })
        await #expect(throws: CommandError.self) { try await running.value }
        await host.stop()
    }

    @Test("A paired device without the grant can't run commands, see projects or start commands in a session")
    func grants() async throws {
        let host = try await ExecHost.make()
        let phone = try await host.connect(ExecHost.device, name: "phone")
        let refusal = await #expect(throws: CommandError.self) {
            try await RemoteCommandRunner(client: phone).run(Command("true", in: host.projectPath, environment: [:]))
        }
        if case .refused(let reason)? = refusal {
            #expect(reason.contains("isn't allowed to run commands"))
        } else {
            Issue.record("Expected a refusal, got \(String(describing: refusal))")
        }
        for request in [
            { _ = try await phone.projects() },
            { _ = try await phone.addProject(host.outside.path(percentEncoded: false)) },
            { _ = try await phone.commandsRun() },
        ] as [@Sendable () async throws -> Void] {
            let error = await #expect(throws: RPCError.self) { try await request() }
            #expect(error.flatMap { HostErrorCode($0) } == .notAuthorized)
        }

        // A stdio MCP server or agent options are commands the agent would start for the phone.
        let stdio: JSONValue = .object([
            "name": .string("evil"), "command": .string("/bin/sh"), "args": .array([]), "env": .array([]),
        ])
        let http: JSONValue = .object([
            "type": .string("http"), "name": .string("docs"), "url": .string("https://example.com/mcp"),
            "headers": .array([]),
        ])
        let sessions: [(NewSessionParams, HostErrorCode)] = [
            (NewSessionParams(agentID: "none", cwd: host.projectPath, mcpServers: [stdio]), .notAuthorized),
            (
                NewSessionParams(
                    agentID: "none", cwd: host.projectPath, meta: .object(["claudeCode": .object([:])])),
                .notAuthorized
            ),
            // Past the grant check: only the agent is missing.
            (NewSessionParams(agentID: "none", cwd: host.projectPath, mcpServers: [http]), .unknownAgent),
        ]
        for (params, expected) in sessions {
            let error = await #expect(throws: RPCError.self) { _ = try await phone.newSession(params) }
            #expect(error.flatMap { HostErrorCode($0) } == expected)
        }
        let owned = await #expect(throws: RPCError.self) {
            _ = try await host.owner.newSession(
                NewSessionParams(agentID: "none", cwd: host.projectPath, mcpServers: [stdio]))
        }
        #expect(owned.flatMap { HostErrorCode($0) } == .unknownAgent)

        // With the grant, a paired Mac runs them.
        let mac = try await host.connect(ExecHost.commandingDevice, name: "laptop")
        let result = try await RemoteCommandRunner(client: mac).run(
            Command("pwd", in: host.projectPath, environment: [:]))
        #expect(result.succeeded)
        await phone.stop()
        await mac.stop()
        await host.stop()
    }

    @Test("Folders outside the host's projects are refused, however the path gets there")
    func pathEscapes() async throws {
        let host = try await ExecHost.make()
        let runner = RemoteCommandRunner(client: host.owner)
        let project = host.project
        let files = FileManager.default
        try files.createDirectory(at: project.appending(path: "sub"), withIntermediateDirectories: true)
        try files.createSymbolicLink(at: project.appending(path: "escape"), withDestinationURL: host.outside)
        try files.createSymbolicLink(
            at: project.appending(path: "alias"), withDestinationURL: project.appending(path: "sub"))

        for folder in [
            host.outside.path(percentEncoded: false),
            host.projectPath + "/../outside",
            host.projectPath + "/escape",
            host.projectPath + "/escape/../outside",
            "/",
        ] {
            let error = await #expect(throws: CommandError.self, "\(folder)") {
                try await runner.run(Command("pwd", in: folder, environment: [:]))
            }
            if case .refused(let reason)? = error {
                #expect(reason.contains("isn't inside one of this host's projects"))
            } else {
                Issue.record("\(folder): expected a refusal, got \(String(describing: error))")
            }
        }
        await #expect(throws: RPCError.self) {
            try await runner.run(Command("pwd", in: "project", environment: [:]))
        }

        // A link that stays inside is fine, and the command runs where it leads.
        let inside = try await runner.run(Command("pwd", ["-P"], in: host.projectPath + "/alias", environment: [:]))
        let sub = try #require(ProjectPaths.resolvedPath(host.projectPath + "/sub"))
        #expect(inside.output == sub + "\n")

        // Projects: never the whole disk or home folder; a folder about to be cloned into is made.
        for path in ["/", files.homeDirectoryForCurrentUser.path(percentEncoded: false), "relative"] {
            await #expect(throws: RPCError.self, "\(path)") { _ = try await host.owner.addProject(path) }
        }
        let clone = host.harness.root.appending(path: "clones/app").path(percentEncoded: false)
        let listed = try await host.owner.addProject(clone, create: true)
        #expect(listed.projects.map(\.path).contains(try #require(ProjectPaths.resolvedPath(clone))))
        #expect(try await runner.run(Command("pwd", in: clone, environment: [:])).succeeded)
        _ = try await host.owner.removeProject(clone)
        await #expect(throws: CommandError.self) { try await runner.run(Command("pwd", in: clone, environment: [:])) }
        await host.stop()
    }

    @Test(
        "The worktrees folder the app syncs is reachable, and clients learn it; devices that run commands sync agents")
    func worktreesFolder() async throws {
        let host = try await ExecHost.make()
        let worktrees = host.harness.root.appending(path: "worktrees-dev/tests", directoryHint: .isDirectory)
        let task = worktrees.appending(path: "app/fix-login")
        try FileManager.default.createDirectory(at: task, withIntermediateDirectories: true)
        let runner = RemoteCommandRunner(client: host.owner)
        await #expect(throws: CommandError.self) {
            try await runner.run(Command("pwd", in: task.path(percentEncoded: false), environment: [:]))
        }
        let _: EmptyMessage = try await host.owner.call(
            HostProtocol.Method.syncAgents,
            SyncAgentsParams(agents: [], worktreesFolder: worktrees.path(percentEncoded: false)))
        #expect(try await host.owner.projects().worktreesFolder == worktrees.path(percentEncoded: false))
        #expect(try await runner.run(Command("pwd", in: task.path(percentEncoded: false), environment: [:])).succeeded)

        // A Mac driving a headless host sends its agents, but its own worktrees setting means nothing here.
        let laptop = try await host.connect(ExecHost.commandingDevice, name: "laptop")
        let _: EmptyMessage = try await laptop.call(
            HostProtocol.Method.syncAgents, SyncAgentsParams(agents: [], worktreesFolder: "/Users/someone/elsewhere"))
        #expect(try await laptop.projects().worktreesFolder == worktrees.path(percentEncoded: false))
        let phone = try await host.connect(ExecHost.device, name: "phone")
        let refused = await #expect(throws: RPCError.self) {
            let _: EmptyMessage = try await phone.call(HostProtocol.Method.syncAgents, SyncAgentsParams(agents: []))
        }
        #expect(refused.flatMap { HostErrorCode($0) } == .notAuthorized)
        await laptop.stop()
        await phone.stop()
        await host.stop()
    }

    @Test("Every command is recorded with the client that ran it, apart from what clients are told")
    func journal() async throws {
        let host = try await ExecHost.make()
        let told = Mutex(0)
        await host.owner.addEventHandler { event in
            if case .activity = event { told.withLock { $0 += 1 } }
        }
        let laptop = try await host.connect(ExecHost.commandingDevice, name: "Brayden's MacBook Pro")
        _ = try await RemoteCommandRunner(client: laptop).run(
            Command("sh", ["-c", "exit 0"], in: host.projectPath, environment: [:]))
        await #expect(throws: CommandError.self) {
            try await RemoteCommandRunner(client: laptop).run(
                Command("pwd", in: host.outside.path(percentEncoded: false), environment: [:]))
        }

        let commands = try await host.owner.commandsRun()
        let entry = try #require(commands.last)
        #expect(commands.count == 1, "a refused command never ran")
        #expect(entry.subject == "Brayden's MacBook Pro")
        let project = try #require(ProjectPaths.resolvedPath(host.projectPath))
        #expect(entry.detail == "sh -c 'exit 0' in \(project)")
        #expect(try await host.owner.activity().isEmpty)
        #expect(told.withLock { $0 } == 0)
        await laptop.stop()
        await host.stop()
    }

    /// Polls `value` until it isn't nil, for up to five seconds.
    static func poll<Value: Sendable>(_ value: @Sendable () -> Value?) async throws -> Value {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if let value = value() { return value }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw CancellationError()
    }
}
