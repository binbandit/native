import ACP
import Exec
import Foundation
import Git
import NativeHostClient
import NativeHostProtocol

@testable import Native

// Exercises the app's actual GitStore and repository actions with three machines using one path.
// Run against an isolated Debug build with scripts/tests/host-git.sh pr26.
private actor RecordingRunner: CommandRunner {
    let name: String
    let dirty: Bool
    private var commands: [[String]] = []

    init(_ name: String, dirty: Bool = false) {
        self.name = name
        self.dirty = dirty
    }

    func run(_ command: Command) async throws -> CommandResult {
        commands.append(command.arguments)
        let output: String
        switch command.arguments.first {
        case "rev-parse" where command.arguments.contains("--show-toplevel"):
            output = "/same/repo\n/same/repo/.git\n/same/repo/.git\n"
        case "rev-parse": output = "abc123\n"
        case "status": output = "# branch.oid abc123\0# branch.head \(name)\0" + (dirty ? "? remote.txt\0" : "")
        case "write-tree": output = "\(name)-snapshot\n"
        default: output = ""
        }
        return CommandResult(exitCode: 0, standardOutput: Data(output.utf8), standardError: Data())
    }

    func count(_ command: String) -> Int { commands.count { $0.contains(command) } }
}

private struct NoMonitor: RepositoryMonitor {
    func changes(in repository: Repository) -> AsyncStream<RepositoryChange> {
        AsyncStream { $0.finish() }
    }
}

@main
@MainActor
private struct HostGitRegression {
    static func main() async {
        do {
            try await run()
        } catch {
            print("FAIL: \(error)")
            exit(1)
        }
    }

    private static func run() async throws {
        let path = URL(filePath: "/same/repo", directoryHint: .isDirectory)
        let localKey = SessionKey(agent: .init(rawValue: "test"), id: SessionID("local"))
        let firstKey = SessionKey(agent: .init(rawValue: "test"), id: SessionID("first"))
        let secondKey = SessionKey(agent: .init(rawValue: "test"), id: SessionID("second"))
        let missingKey = SessionKey(agent: .init(rawValue: "test"), id: SessionID("missing"))
        let localRunner = RecordingRunner("local")
        let firstRunner = RecordingRunner("first")
        let secondRunner = RecordingRunner("second")
        let baselines = GitTurnBaselines(defaults: PreviewUserDefaults())
        func store(_ runner: RecordingRunner, local: Bool) -> GitStore {
            #if BEFORE
            return GitStore(environment: { [:] }, turnBaselines: baselines) { _ in
                Git(environment: [:], runner: runner, monitor: NoMonitor())
            }
            #else
            return GitStore(environment: { [:] }, isLocal: local, turnBaselines: baselines) { _ in
                Git(environment: [:], runner: runner, monitor: NoMonitor())
            }
            #endif
        }
        let local = store(localRunner, local: true)
        let first = store(firstRunner, local: false)
        let second = store(secondRunner, local: false)
        #if BEFORE
        local.hostStore = { folder in folder == path ? first : nil }
        let localModel = local.model(for: path)
        let firstModel = local.model(for: path)
        let secondModel = local.model(for: path)
        #else
        local.sessionStore = { key in
            switch key {
            case firstKey: first
            case secondKey: second
            case missingKey: nil
            default: local
            }
        }
        let localModel = local.model(for: path, session: localKey)
        let firstModel = local.model(for: path, session: firstKey)
        let secondModel = local.model(for: path, session: secondKey)
        #endif
        try require(localModel !== firstModel, "local and paired host share a repository model")
        try require(firstModel !== secondModel, "two paired hosts share a repository model")
        await localModel.refreshNow()
        await firstModel.refreshNow()
        await secondModel.refreshNow()
        try require(localModel.branch?.name == "local", "local status used another machine")
        try require(firstModel.branch?.name == "first", "first host status used another machine")
        try require(secondModel.branch?.name == "second", "second host status used another machine")
        let change = FileChange(path: "same.txt", kind: .modified, area: .unstaged)
        await secondModel.stage([change])
        try require(await secondRunner.count("add") == 1, "stage did not reach the selected host")
        try require(await firstRunner.count("add") == 0, "stage reached the first host")
        try require(await localRunner.count("add") == 0, "stage reached this Mac")
        #if !BEFORE
        try require(local.model(for: path) === localModel, "folder-only lookup did not stay local")
        try require(localModel.localRoot == path, "local file actions lost their root")
        try require(firstModel.localRoot == nil && secondModel.localRoot == nil, "remote files have local actions")
        let missing = local.model(for: path, session: missingKey)
        guard case .failed = missing.state else { throw Failure("unavailable host fell back to this Mac") }
        try require(missing.localRoot == nil, "unavailable host has local file actions")
        await missing.refreshNow()
        guard case .failed = missing.state else {
            throw Failure("retry changed an unavailable host into a local repository")
        }
        let firstScans = await firstRunner.count("status")
        let secondScans = await secondRunner.count("status")
        local.refresh(folder: path, session: secondKey)
        try await Task.sleep(for: .milliseconds(50))
        try require(await firstRunner.count("status") == firstScans, "refresh reached the first host")
        try require(await secondRunner.count("status") > secondScans, "refresh missed the selected host")
        let firstSettled = await firstRunner.count("status")
        local.refreshWhenSettled(folder: path, session: firstKey)
        try await Task.sleep(for: .milliseconds(1200))
        try require(await firstRunner.count("status") > firstSettled, "settled refresh missed its host")
        let date = Date()
        for key in [localKey, firstKey, secondKey] {
            local.recordTurnStart(of: key, at: date, in: path)
        }
        for _ in 0..<100 {
            if baselines.baseline(of: secondKey, startedAt: date) != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        for (key, name) in [(localKey, "local"), (firstKey, "first"), (secondKey, "second")] {
            try require(
                baselines.baseline(of: key, startedAt: date)?.snapshot.tree == "\(name)-snapshot",
                "turn baseline used the wrong machine for \(name)")
        }
        try await sidebarPreservesSessionIdentity()
        try await wiringPreservesClientIdentity(local: local, runner: localRunner, path: path)
        #endif
        print(
            "PASS: colliding paths preserve machine identity for models, stage, refresh and turn baselines; remote file roots are withheld; sidebar and re-pairing routing pass"
        )
    }

    #if !BEFORE
    private static func sidebarPreservesSessionIdentity() async throws {
        let app = AppModel.preview(.empty)
        guard let agent = app.plugins.agents.first else { throw Failure("missing fixture agent") }
        let project = app.projects.add(URL(filePath: "/pr26-project"))
        let cleanRunner = RecordingRunner("local-branch")
        let dirtyRunner = RecordingRunner("remote-branch", dirty: true)
        let local = GitStore(environment: { [:] }) { _ in
            Git(environment: [:], runner: cleanRunner, monitor: NoMonitor())
        }
        let remote = GitStore(environment: { [:] }, isLocal: false) { _ in
            Git(environment: [:], runner: dirtyRunner, monitor: NoMonitor())
        }
        local.sessionStore = { _ in remote }
        let gitHub = GitHubModel(environment: { _ in [:] }, runner: cleanRunner)
        let insights = AppSidebarTaskInsights.make(model: app, git: local, gitHub: gitHub)
        let tasks = AppTaskPullRequests(model: app, git: local, gitHub: gitHub)
        for path in ["/same/repo", "/pr26-remote-only/checkout"] {
            let summary = SessionSummary(
                project: project.id, agent: agent,
                info: SessionInfo(sessionId: SessionID(path), cwd: path, title: "Remote task"))
            await local.model(for: URL(filePath: path)).refreshNow()
            await insights.prepare([summary])
            try require(insights.hasUncommittedChanges(summary), "sidebar lost remote changes at \(path)")
            try require(tasks.branch(of: summary) == nil, "remote task inherited a local PR branch at \(path)")
            try require(tasks.menu(of: summary) == nil, "remote task inherited local PR actions")
        }
    }

    private static func wiringPreservesClientIdentity(local: GitStore, runner: RecordingRunner, path: URL) async throws
    {
        let app = AppModel.preview(.empty)
        guard let agent = app.plugins.agents.first else { throw Failure("missing fixture agent") }
        func client() -> NativeHostClient {
            NativeHostClient(transport: NeverConnect(), clientInfo: PeerInfo(name: "test", version: "0", build: "0"))
        }
        let localClient = client()
        let firstClient = client()
        let secondClient = client()
        app.runtimes.host = localClient
        let gitHub = GitHubModel(environment: { _ in [:] }, runner: runner)
        let scripts = TaskScriptCenter(settings: TaskScriptSettings(), runner: runner)
        let provider = GitTaskWorkspaceProvider(git: local, gitHub: gitHub, scripts: scripts)
        RemoteHostsWiring.connect(model: app, local: provider, git: local, gitHub: gitHub)
        guard let makeWorkspaces = app.hosts.makeTaskWorkspaces else { throw Failure("remote wiring is disabled") }
        let firstHost = RemoteHostID()
        let secondHost = RemoteHostID()
        _ = makeWorkspaces(firstHost, firstClient, path)
        _ = makeWorkspaces(secondHost, secondClient, path)
        func session(_ id: String, on client: NativeHostClient) -> SessionModel {
            let key = SessionID(id)
            let summary = HostSessionSummary(
                id: HostSessionID(), agentID: agent.id.rawValue, agentName: agent.displayName,
                agentSessionID: key, cwd: path.path(), phase: .idle)
            let session = SessionModel(
                agent: agent, id: key, summary: summary, client: client, services: app.sessions.services,
                promptCapabilities: PromptCapabilities(), origin: .user, parent: nil)
            app.sessions.register(session)
            return session
        }
        let here = session("wired-local", on: localClient)
        let there = session("wired-first", on: firstClient)
        let elsewhere = session("wired-second", on: secondClient)
        let hereModel = local.model(for: path, session: here.key)
        let thereModel = local.model(for: path, session: there.key)
        let elsewhereModel = local.model(for: path, session: elsewhere.key)
        try require(hereModel === local.model(for: path), "wiring redirected a local session")
        try require(thereModel !== hereModel && thereModel !== elsewhereModel, "wiring merged different clients")
        try require(!thereModel.isLocal && !elsewhereModel.isLocal, "wiring lost remote locality")
        let replacementClient = client()
        _ = makeWorkspaces(firstHost, replacementClient, path)
        let replacementModel = local.model(for: path, session: there.key)
        try require(replacementModel !== thereModel, "re-pairing left Git on the retired client")
        let replacementGit = await replacementModel.resolveGit()
        let replacementRunner = replacementGit?.runner as? RemoteCommandRunner
        try require(replacementRunner?.client === replacementClient, "Git operations still target the retired client")
        try require(
            local.model(for: path, session: elsewhere.key) === elsewhereModel, "re-pairing changed another host")
        // These clients have no pairing entries: open tasks must still never fall back to local Git.
        let unavailable = session("unpaired-without-store", on: client())
        guard case .failed = local.model(for: path, session: unavailable.key).state else {
            throw Failure("unpaired session without a store fell back to local Git")
        }
    }

    private struct NeverConnect: HostTransport {
        var displayName: String { "Unstarted test host" }
        func connect() async throws -> any ByteStream { throw Failure("test transport must never connect") }
    }
    #endif

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(message) }
    }

    private struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
}
