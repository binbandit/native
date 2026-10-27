import ACP
import Exec
import Foundation
import Git
import GitHub
import NativeHostClient
import NativeHostProtocol
import NativePolicy

@testable import Native
@testable import NativeLink

// A paired host's task finds its pull request with gh on that host. This Mac and two droids hold the
// same checkout path on the same branch, each with its own pull request; droids are fake host
// processes behind real clients, so every lookup goes through RemoteCommandRunner. Fixed gh JSON
// only: nothing reaches GitHub. Run against an isolated Debug build with
// scripts/tests/droid-pr-lookup.sh <instance>.

private struct LookupFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// What one machine's git and gh say. Every machine has the task's checkout at the same path on the
/// same branch; each has its own pull request, and some a branch note naming it (Open as Task's).
private struct Machine: Sendable {
    enum GitHubCLIState: Sendable { case ready, missing, signedOut }

    static let folder = "/same/worktrees/task"
    static let branch = "task/shared"

    var pullRequest: Int
    var title: String
    var linked = false
    var gh = GitHubCLIState.ready
    var login = "droid"

    var url: String { "https://github.com/acme/app/pull/\(pullRequest)" }

    enum Reply: Sendable {
        case output(Int32, String, String)
        case notInstalled
    }

    func answer(_ executable: String, _ arguments: [String]) -> Reply {
        if executable == "git" { return git(arguments) }
        switch gh {
        case .missing: return .notInstalled
        case .signedOut: return .output(4, "", "To get started with GitHub CLI, please run:  gh auth login")
        case .ready: return github(arguments)
        }
    }

    private func git(_ arguments: [String]) -> Reply {
        if arguments.contains("--show-toplevel") {
            return .output(0, "\(Self.folder)\n/same/repo/.git/worktrees/task\n/same/repo/.git\n", "")
        }
        if arguments.contains("rev-parse") { return .output(0, "abc123\n", "") }
        if arguments.contains("status") {
            return .output(0, "# branch.oid abc123\0# branch.head \(Self.branch)\0", "")
        }
        if arguments.first == "remote" {
            return .output(0, "origin\thttps://github.com/acme/app.git (fetch)\n", "")
        }
        if arguments.first == "config", arguments.contains(where: { $0.contains("nativePullRequest") }) {
            return linked ? .output(0, "branch.\(Self.branch).nativepullrequest\n\(url)\0", "") : .output(1, "", "")
        }
        if arguments.first == "config", arguments.contains(where: { $0.contains("gh-resolved") }) {
            return .output(1, "", "")
        }
        return .output(0, "", "")
    }

    private func github(_ arguments: [String]) -> Reply {
        let json = """
            {"number":\(pullRequest),"title":"\(title)","url":"\(url)","state":"OPEN","isDraft":false,\
            "headRefName":"\(Self.branch)","baseRefName":"main","createdAt":"2026-10-01T00:00:00Z",\
            "updatedAt":"2026-10-01T00:00:00Z"}
            """
        switch Array(arguments.prefix(2)) {
        case ["pr", "list"]: return .output(0, "[\(json)]", "")
        case ["pr", "view"] where arguments.count > 2 && arguments[2] == url: return .output(0, json, "")
        case ["auth", "status"]:
            let account = #"{"state":"success","active":true,"host":"github.com","login":"\#(login)"}"#
            return .output(0, #"{"hosts":{"github.com":[\#(account)]}}"#, "")
        default: break
        }
        if arguments.first == "api" { return .output(0, #"{"login":"\#(login)"}"#, "") }
        if arguments.first == "search" { return .output(0, "[]", "") }
        return .output(1, "", "unknown command: gh \(arguments.joined(separator: " "))")
    }
}

/// This Mac's git and gh, recorded. Its next pull request lookup can wait to be released.
private actor RecordingRunner: CommandRunner {
    private var machine: Machine
    private(set) var commands: [Command] = []
    private var holdsNextLookup = false
    private(set) var isHolding = false
    private var held: CheckedContinuation<Void, Never>?

    init(_ machine: Machine) { self.machine = machine }

    func run(_ command: Command) async throws -> CommandResult {
        commands.append(command)
        if command.executable == "gh", command.arguments.first == "pr", holdsNextLookup {
            holdsNextLookup = false
            isHolding = true
            await withCheckedContinuation { held = $0 }
            isHolding = false
        }
        switch machine.answer(command.executable, command.arguments) {
        case .notInstalled: throw CommandError.notFound(command.executable)
        case .output(let code, let output, let error):
            return CommandResult(exitCode: code, standardOutput: Data(output.utf8), standardError: Data(error.utf8))
        }
    }

    func holdNextLookup() { holdsNextLookup = true }
    func release() {
        held?.resume()
        held = nil
    }
    func set(_ machine: Machine) { self.machine = machine }
    var lookups: [Command] { commands.filter { $0.executable == "gh" && $0.arguments.first == "pr" } }
}

/// One pairing's connection to a fake droid, recording every command the droid runs for it.
private actor DroidLink: HostTransport {
    nonisolated let displayName: String
    nonisolated let hostID: RemoteHostID
    private let session: HostSessionSummary
    private let epoch = UUID()
    private var machine: Machine
    private var peer: JSONRPCPeer?
    private(set) var runs: [ExecRunParams] = []
    private var isOffline = false
    private var holdsNextLookup = false
    private(set) var isHolding = false
    private var held: CheckedContinuation<Void, Never>?

    init(_ name: String, hostID: RemoteHostID = RemoteHostID(), session: String, machine: Machine) {
        displayName = name
        self.hostID = hostID
        self.session = HostSessionSummary(
            id: HostSessionID(), agentID: "fixture", agentName: "Fixture", agentSessionID: SessionID(session),
            cwd: Machine.folder, title: session, phase: .idle)
        self.machine = machine
    }

    func set(_ machine: Machine) { self.machine = machine }
    func holdNextLookup() { holdsNextLookup = true }
    func release() {
        held?.resume()
        held = nil
    }

    /// The droid drops off the network until `reconnect()`.
    func drop() {
        isOffline = true
        peer?.close()
        peer = nil
    }

    func reconnect() { isOffline = false }

    var lookups: [ExecRunParams] { runs.filter { $0.executable == "gh" && $0.arguments.first == "pr" } }

    func connect() async throws -> any ByteStream {
        guard !isOffline else { throw LookupFailure("\(displayName) is offline") }
        let (clientEnd, hostEnd) = try UnixSocket.pair()
        let peer = JSONRPCPeer(channel: ByteChannel.socket(hostEnd, label: "droid-host"), label: "droid-host") {
            [weak self] event in
            if case .request(let message) = event { Task { await self?.receive(message) } }
        }
        self.peer = peer
        peer.start()
        return ByteChannel.socket(clientEnd, label: "droid-client")
    }

    private func receive(_ message: JSONRPCPeer.Message) async {
        guard let id = message.id, let peer else { return }
        // A dropped connection can't be answered; the client reports that itself.
        try? await answer(message, id: id, on: peer)
    }

    private func answer(_ message: JSONRPCPeer.Message, id: RequestID, on peer: JSONRPCPeer) async throws {
        switch message.method {
        case HostProtocol.Method.initialize:
            try peer.respond(
                to: id,
                with: HostInfo(
                    protocolVersion: HostProtocol.version, hostID: hostID, machineName: displayName,
                    hostInfo: PeerInfo(name: "Fixture", version: "1", build: "1"), epoch: epoch, processID: 1,
                    startedAt: .now, channel: "tests"))
        case HostProtocol.Method.listAgents: try peer.respond(to: id, with: [HostAgent]())
        case HostProtocol.Method.listSessions: try peer.respond(to: id, with: [session])
        case HostProtocol.Method.listProjects:
            try peer.respond(to: id, with: HostProjectList(projects: [], worktreesFolder: "/same/worktrees"))
        case HostProtocol.Method.execRun:
            let params = try message.params(as: ExecRunParams.self)
            runs.append(params)
            if params.executable == "gh", params.arguments.first == "pr", holdsNextLookup {
                holdsNextLookup = false
                isHolding = true
                await withCheckedContinuation { held = $0 }
                isHolding = false
            }
            switch machine.answer(params.executable, params.arguments) {
            case .notInstalled:
                try peer.respond(to: id, error: HostErrorCode.commandNotFound.rpcError("gh isn't on the PATH"))
            case .output(let code, let output, let error):
                try peer.respond(
                    to: id, with: ExecRunResult(exitCode: code, stdout: Data(output.utf8), stderr: Data(error.utf8)))
            }
        case HostProtocol.Method.execCancel, HostProtocol.Method.configureTitles:
            try peer.respond(to: id, with: EmptyMessage())
        default:
            try peer.respond(to: id, error: .methodNotFound(message.method))
        }
    }
}

private struct NoMonitor: RepositoryMonitor {
    func changes(in repository: Repository) -> AsyncStream<RepositoryChange> {
        AsyncStream { $0.finish() }
    }
}

@main
@MainActor
private struct DroidPullRequestLookupRegression {
    static func main() async {
        do { try await run() } catch {
            print("FAIL: \(error)")
            exit(1)
        }
    }

    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw LookupFailure(message) }
    }

    static func wait(_ what: String, _ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while !(await condition()) {
            guard ContinuousClock.now < deadline else { throw LookupFailure("Timed out: \(what)") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    /// What a host's gh must not get from this Mac: its PATH, home, account or GitHub host.
    static func carriesNothingOfThisMac(_ runs: [ExecRunParams]) -> Bool {
        let foreign: Set<String> = ["PATH", "HOME", "GH_HOST", "GH_TOKEN", "GH_CONFIG_DIR", "GH_REPO", "GH_DEBUG"]
        return runs.allSatisfy { $0.environment.keys.allSatisfy { !foreign.contains($0) } }
    }

    static func run() async throws {
        try policyRefusesGitHubOnHosts()

        let scratch = FileManager.default.temporaryDirectory.appending(path: "droid-pr-lookup-\(UUID())")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let defaults = PreviewUserDefaults()
        let manifest = PluginManifest(
            id: "fixture", name: "Fixture",
            agents: [AgentManifest(id: "fixture", name: "Fixture", command: "/usr/bin/true")])
        let app = AppModel(
            plugins: PluginRegistry(builtIns: [ManifestPlugin(manifest: manifest)], defaults: defaults),
            defaults: defaults, catalogURL: nil,
            hosts: RemoteHosts(store: FilePairedHostStore(directory: scratch.appending(path: "hosts"))))
        guard let agent = app.plugins.agents.first else { throw LookupFailure("No fixture agent") }
        let project = app.projects.add(URL(filePath: "/same/repo"))

        // This Mac, wired as the app wires it.
        let here = RecordingRunner(Machine(pullRequest: 1, title: "On this Mac", linked: true, login: "other"))
        let git = GitStore(environment: { [:] }) { _ in Git(environment: [:], runner: here, monitor: NoMonitor()) }
        let gitHub = GitHubModel(environment: { _ in [:] }, runner: here, defaults: PreviewUserDefaults())
        gitHub.linkedPullRequest = { [git] in await GitHubGitWiring.linkedPullRequest(for: $0, git: git) }
        let scripts = TaskScriptCenter(settings: TaskScriptSettings(), runner: here)
        RemoteHostsWiring.connect(
            model: app, local: GitTaskWorkspaceProvider(git: git, gitHub: gitHub, scripts: scripts), git: git,
            gitHub: gitHub)
        try require(app.hosts.makeTaskWorkspaces != nil, "Remote hosts are off: run with -NativeRemoteHosts YES")
        let tasks = AppTaskPullRequests(model: app, git: git, gitHub: gitHub)

        func pair(
            _ link: DroidLink, key: LinkPublicKey, runCommands: Bool = true
        ) async throws -> (
            RemoteHost, NativeHostClient
        ) {
            let client = NativeHostClient(
                transport: link, clientInfo: PeerInfo(name: "Fixture", version: "1", build: "1"))
            let remote = app.hosts.add(
                PairedHost(
                    result: LinkPairingResult(
                        hostID: link.hostID, hostKey: key, hostName: link.displayName, deviceID: UUID(),
                        grants: LinkGrants(runCommands: runCommands), addresses: []),
                    identity: LinkIdentity()))
            remote.start(using: client)
            try await wait("\(link.displayName) lists its task") { !remote.sessions.isEmpty }
            // What the app does once a host connects (refreshRemoteHistory): make its task workspaces.
            _ = await app.taskWorkspaces(on: remote)
            return (remote, client)
        }
        func task(_ id: String) -> SessionSummary {
            SessionSummary(
                project: project.id, agent: agent,
                info: SessionInfo(sessionId: SessionID(id), cwd: Machine.folder, title: id))
        }
        let folder = URL(filePath: Machine.folder, directoryHint: .isDirectory)

        let keyA = LinkIdentity().publicKey
        let linkA = DroidLink("Droid A", session: "task-a", machine: Machine(pullRequest: 2, title: "On droid A"))
        let linkB = DroidLink(
            "Droid B", session: "task-b", machine: Machine(pullRequest: 3, title: "On droid B", linked: true))
        let (a, _) = try await pair(linkA, key: keyA)
        let (b, clientB) = try await pair(linkB, key: LinkIdentity().publicKey)
        let local = task("local-task")
        let taskA = task("task-a")
        let taskB = task("task-b")

        // This Mac's row badge looks its branch up.
        await git.model(for: folder, session: local.id).refreshNow()
        guard let localBranch = tasks.branch(of: local) else { throw LookupFailure("This Mac's task has no branch") }
        try require(await gitHub.loadPullRequest(for: localBranch) == nil, "This Mac's lookup failed")
        // Read-only row outcomes start from nothing cached for either host.
        let insights = AppSidebarTaskInsights.make(model: app, git: git, gitHub: gitHub)
        try require(gitHub.branchPullRequests.keys.allSatisfy { $0.host == nil }, "A droid's answer was cached early")
        try await wait("droid A's row finds its pull request") { insights.pullRequestBadge(taskA) != nil }
        try await wait("droid B's row finds its pull request") { insights.pullRequestBadge(taskB) != nil }
        try require(insights.hasPullRequest(taskA) && insights.hasPullRequest(taskB), "The pull request filter missed")

        // One path and branch on three machines: three references, each answered by its own gh.
        guard let branchA = tasks.branch(of: taskA), let branchB = tasks.branch(of: taskB) else {
            throw LookupFailure("A droid's task has no branch")
        }
        try require(localBranch.host == nil && branchA.host == a.id && branchB.host == b.id, "Branches lost their host")
        try require(
            Set([localBranch, branchA, branchB].map { "\($0.directory.path)|\($0.branch)" }).count == 1,
            "The fixture's machines don't share one path and branch")
        try require(tasks.pullRequest(of: local)?.number == 1, "This Mac's task got another machine's pull request")
        try require(tasks.pullRequest(of: taskA)?.number == 2, "Droid A's task didn't get droid A's pull request")
        try require(tasks.pullRequest(of: taskB)?.number == 3, "Droid B's task didn't get droid B's pull request")
        try require(await here.lookups.count == 1, "This Mac's gh answered for a droid")
        let listedOnA = await linkA.lookups
        try require(
            listedOnA.count == 1 && listedOnA[0].arguments.prefix(2) == ["pr", "list"]
                && listedOnA[0].arguments.contains("--head=\(Machine.branch)")
                && listedOnA[0].directory?.hasPrefix(Machine.folder) == true,
            "Droid A didn't look its branch up in its checkout")
        // Droid B's branch note names its pull request; this Mac's note (#1) never reaches a droid.
        let viewedOnB = await linkB.lookups
        try require(
            viewedOnB.count == 1
                && viewedOnB[0].arguments.prefix(3) == ["pr", "view", "https://github.com/acme/app/pull/3"],
            "Droid B's branch note wasn't read with droid B's git")
        let notesHere = await here.commands.count { $0.arguments.contains { $0.contains("nativePullRequest") } }
        try require(notesHere == 1, "This Mac's branch notes were read for a droid's branch")
        let allRuns = await linkA.runs + linkB.runs
        try require(carriesNothingOfThisMac(allRuns), "A droid's gh got this Mac's environment or account")
        print("PASS: one path and branch on this Mac and two droids gives three pull requests, each from its own gh")

        // Fresh answers come from the cache; an explicit refresh asks the droid again, and only it.
        try require(await gitHub.loadPullRequest(for: branchA) == nil, "Cached lookup failed")
        try require(await linkA.lookups.count == 1, "A fresh answer asked the droid again")
        await linkA.set(Machine(pullRequest: 2, title: "Renamed on droid A"))
        try require(await gitHub.loadPullRequest(for: branchA, maxAge: 0) == nil, "Refresh failed")
        try require(gitHub.pullRequest(for: branchA)?.title == "Renamed on droid A", "Refresh kept the old answer")
        let counts = (await linkA.lookups.count, await linkB.lookups.count, await here.lookups.count)
        try require(counts == (2, 1, 1), "Refreshing droid A's branch asked another machine")
        print("PASS: an explicit refresh asks the task's own droid, and the cache spares it otherwise")

        // A droid's pull request is read-only: no Merge, no Native page acting as this Mac's account.
        try require(
            tasks.menu(of: taskA)?.items.map(\.title) == ["Open on GitHub", "Copy Link"],
            "A droid's task offers pull request writes")
        try require(
            tasks.menu(of: local)?.items.map(\.title) == ["Open in Native", "Open on GitHub", "Copy Link", "Merge…"],
            "This Mac's task lost its pull request actions")
        try require(insights.pullRequestBadge(taskA) != nil, "Paired-host task has no read-only outcome badge")
        try require(insights.pullRequestBadge(taskB) != nil, "Second host lost its own outcome badge")
        var opened: URL?
        gitHub.openExternally = { opened = $0 }
        insights.pullRequestMenu(taskA)?.items.first { $0.title == "Open on GitHub" }?.perform()
        try require(opened == tasks.pullRequest(of: taskA)?.url, "Paired-host menu opened another PR")
        // The catalog's index, as the agents' listings fill it.
        app.catalog.remote = [local.id: (project.id, local.info), taskA.id: (project.id, taskA.info)]
        try require(tasks.branch(for: taskA.id) == branchA, "A droid's task by key lost its branch")
        try require(tasks.pullRequest(for: taskA.id) == nil, "Open Pull Request reaches a droid's pull request")
        try require(tasks.pullRequest(for: local.id)?.number == 1, "Open Pull Request lost this Mac's pull request")
        print("PASS: a droid's pull request opens on GitHub only; merging and the Native page stay this Mac's")

        // Switching this Mac's account neither drops a droid's lookup in flight nor clears its answers.
        await linkA.holdNextLookup()
        let acrossSwitch = Task { await gitHub.loadPullRequest(for: branchA, maxAge: 0) }
        try await wait("droid A holds its lookup") { await linkA.isHolding }
        let answerB = gitHub.branchPullRequest(for: branchB)
        await gitHub.selectAccount(
            AuthStatus.Account(host: "github.com", login: "other", active: true, state: .success))
        try require(gitHub.accounts.current?.login == "other", "This Mac's account didn't switch")
        try require(gitHub.branchPullRequest(for: branchB) == answerB, "Switching here cleared a droid's answer")
        try await wait("this Mac's branch reloads for its new account") { gitHub.pullRequest(for: localBranch) != nil }
        let pinned = await here.lookups.last?.environment["GH_HOST"]
        try require(pinned == "github.com", "This Mac's lookup didn't use its selected account")
        await linkA.set(Machine(pullRequest: 2, title: "Answered across the switch"))
        await linkA.release()
        let switched = await acrossSwitch.value
        try require(switched == nil, "Switching here dropped a droid's lookup: \(String(describing: switched))")
        try require(gitHub.pullRequest(for: branchA)?.title == "Answered across the switch", "Lost a droid's answer")
        let runsOnA = await linkA.runs
        try require(carriesNothingOfThisMac(runsOnA), "This Mac's account choice reached droid A")
        try require(
            // GitHubCLI's account check: gh's login status and the remotes gh resolved.
            !runsOnA.contains { $0.arguments.first == "auth" || $0.arguments.contains { $0.contains("gh-resolved") } },
            "This Mac's account check ran on droid A")
        print("PASS: switching this Mac's account leaves droids' lookups and answers alone")

        // Failures keep the last answer and say why; this Mac's gh is never asked instead.
        let lookupsHere = await here.lookups.count
        let answered = gitHub.pullRequest(for: branchA)
        var droidA = Machine(pullRequest: 2, title: "Answered across the switch")
        droidA.gh = .missing
        await linkA.set(droidA)
        try require(await gitHub.loadPullRequest(for: branchA, maxAge: 0) == .notInstalled, "Missing gh not reported")
        try require(gitHub.pullRequest(for: branchA) == answered, "Missing gh dropped the last answer")
        droidA.gh = .signedOut
        await linkA.set(droidA)
        guard case .notAuthenticated? = await gitHub.loadPullRequest(for: branchA, maxAge: 0) else {
            throw LookupFailure("Signed-out gh not reported")
        }
        try require(gitHub.branchPullRequest(for: branchA)?.pullRequest == answered, "Signing out dropped the answer")
        try require(
            gitHub.availability != .notAuthenticated && gitHub.accounts.error == nil,
            "A droid signing out signed this Mac out")
        droidA.gh = .ready
        await linkA.set(droidA)
        await linkB.drop()
        try await wait("droid B goes offline") { await clientB.hostInfo == nil }
        guard case .offline? = await gitHub.loadPullRequest(for: branchB, maxAge: 0) else {
            throw LookupFailure("An offline droid wasn't reported")
        }
        try require(gitHub.pullRequest(for: branchB)?.number == 3, "Going offline dropped droid B's answer")
        guard case .offline? = gitHub.branchPullRequest(for: branchB)?.failure else {
            throw LookupFailure("Droid B's answer doesn't say it's stale")
        }
        try require(await here.lookups.count == lookupsHere, "A droid's failure fell back to this Mac's gh")
        await linkB.reconnect()
        try await wait("droid B reconnects") { await clientB.hostInfo != nil }
        try require(await gitHub.loadPullRequest(for: branchB, maxAge: 0) == nil, "Lookup failed after reconnecting")
        try require(gitHub.branchPullRequest(for: branchB)?.failure == nil, "Reconnecting kept the failure")
        let refusal = gitHub.remoteBranches.refusal
        gitHub.remoteBranches.refusal = { "Paired hosts are off for this check." }
        let runsBeforeRefusal = await linkA.runs.count
        guard case .failed(_, let message)? = await gitHub.loadPullRequest(for: branchA, maxAge: 0),
            message == "Paired hosts are off for this check."
        else { throw LookupFailure("A policy refusal wasn't reported") }
        try require(await linkA.runs.count == runsBeforeRefusal, "A refused lookup reached the droid")
        gitHub.remoteBranches.refusal = refusal
        print("PASS: missing gh, signed-out gh, an offline droid and policy keep the stale answer and say why")

        // Without the runCommands grant a droid has no gh to ask, and nothing runs anywhere.
        let linkC = DroidLink("Droid C", session: "task-c", machine: Machine(pullRequest: 4, title: "On droid C"))
        let (c, _) = try await pair(linkC, key: LinkIdentity().publicKey, runCommands: false)
        let taskC = task("task-c")
        await git.model(for: folder, session: taskC.id).refreshNow()
        try require(tasks.branch(of: taskC) == nil, "A droid without runCommands has a branch to look up")
        let branchC = BranchReference(host: c.id, directory: folder, branch: Machine.branch)
        guard case .offline? = await gitHub.loadPullRequest(for: branchC, maxAge: 0) else {
            throw LookupFailure("A droid without runCommands wasn't reported unavailable")
        }
        try require(await linkC.runs.isEmpty, "A droid without runCommands ran commands")
        try require(await here.lookups.count == lookupsHere, "A droid without runCommands used this Mac's gh")
        print("PASS: a droid paired without runCommands is unavailable, never answered here")

        try await pairingAgainDropsTheOldAnswer(gitHub)
        let runsOnOldA = await linkA.runs.count
        let linkA2 = DroidLink(
            "Droid A", hostID: a.id, session: "task-a", machine: Machine(pullRequest: 20, title: "After pairing again"))
        _ = try await pair(linkA2, key: keyA)
        try require(gitHub.pullRequest(for: branchA) == nil, "Pairing again kept the old pairing's answer")
        // The row asks again through the new pairing's git and gh.
        try await wait("the new pairing answers the row") { tasks.pullRequest(of: taskA)?.number == 20 }
        try require(tasks.branch(of: taskA) == branchA, "Pairing again changed the task's branch")
        try require(await linkA2.lookups.count == 1, "The new pairing was asked more than once")
        try require(await linkA.runs.count == runsOnOldA, "The replaced pairing still ran commands")
        print("PASS: pairing a droid again asks the new pairing")
    }

    /// A late answer from a replaced pairing is dropped; the next lookup asks the new one.
    static func pairingAgainDropsTheOldAnswer(_ gitHub: GitHubModel) async throws {
        let host = RemoteHostID()
        let branch = BranchReference(host: host, directory: URL(filePath: "/droid-d/task"), branch: Machine.branch)
        let old = RecordingRunner(Machine(pullRequest: 99, title: "From the replaced pairing"))
        let new = RecordingRunner(Machine(pullRequest: 41, title: "From the new pairing"))
        gitHub.answerBranches(on: host, with: old) { _ in nil }
        await old.holdNextLookup()
        let late = Task { await gitHub.loadPullRequest(for: branch, maxAge: 0) }
        try await wait("the old pairing holds its lookup") { await old.isHolding }
        gitHub.answerBranches(on: host, with: new) { _ in nil }
        await old.release()
        try require(await late.value == .cancelled, "A replaced pairing's answer counted")
        try require(gitHub.pullRequest(for: branch) == nil, "A replaced pairing's answer was shown")
        try require(await gitHub.loadPullRequest(for: branch) == nil, "The new pairing's lookup failed")
        try require(gitHub.pullRequest(for: branch)?.number == 41, "The new pairing wasn't asked")
        let asked = (await old.lookups.count, await new.lookups.count)
        try require(asked == (1, 1), "A pairing was asked twice")
        print("PASS: a replaced pairing's late answer is dropped")
    }

    /// Organizations can turn gh on paired hosts off, and restricted deployments always do for now.
    static func policyRefusesGitHubOnHosts() throws {
        try require(RemoteHostsWiring.gitHubRefusal(NativePolicy()) == nil, "Ordinary policy refused gh on hosts")
        var noHosts = NativePolicy()
        noHosts.remoteHostsEnabled = false
        var noGitHub = NativePolicy()
        noGitHub.network.services[.github] = .init(enabled: false)
        var restricted = NativePolicy()
        restricted.network.mode = .internalOnly
        restricted.network.services[.github] = .init(enabled: true)
        var malformed = NativePolicy()
        malformed.network.isValid = false
        for policy in [noHosts, noGitHub, restricted, malformed] {
            try require(RemoteHostsWiring.gitHubRefusal(policy) != nil, "Policy didn't refuse gh on hosts")
        }
        print("PASS: managed policy refuses gh on paired hosts")
    }
}
