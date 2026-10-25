import ACP
import Exec
import Foundation
import NativeHostClient
import NativeHostProtocol
import Synchronization
import Testing

@testable import NativeHost

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The organization's policy on a host nobody's app is attached to (docs/enterprise/host-policy.md):
/// a scratch host in this process whose policy the test changes, with everything the policy has to
/// stop counted instead of done (agent processes, login-shell reads, commands, update checks and the
/// tools listener). Denied means none of those happen at all.
@Suite("Host policy", .serialized, .timeLimit(.minutes(2)))
@HostActor
struct HostPolicyTests {
    nonisolated static let restricted = HostPolicy(
        mode: .restricted, capabilities: Set(HostCapability.allCases), reason: "It's a restricted deployment.")
    nonisolated static let onlyOther = HostPolicy(
        mode: .ordinary, capabilities: Set(HostCapability.allCases), allowedAgents: ["other"])
    nonisolated static let pairedDevice = ClientGrants(
        managePlugins: true, manageHost: true, isLocal: false, runCommands: true)

    @Test("A restricted host recovers nothing at startup: the turn ends with the reason, queues wait, nothing runs")
    func deniedStartupRecovery() async throws {
        // The store a host that crashed mid-turn leaves, read by a restricted host starting on it.
        let previous = try PolicyRig(.unrestricted)
        let session = try previous.seedInterruptedTurn()
        let rig = try PolicyRig(Self.restricted, root: previous.root)
        rig.core.start()

        #expect(try rig.core.store.unfinishedTurns().isEmpty)
        #expect(rig.core.sessions[session]?.record.isQueuePaused == true)
        #expect(rig.core.sessions[session]?.queue.count == 1)
        let recovery = try rig.core.store.activity(after: nil, limit: 50).compactMap(\.recovery).first
        #expect(recovery?.action == .failed)
        #expect(recovery?.problem?.contains("organization's policy doesn't allow this host to start agents") == true)
        try await Task.sleep(for: .milliseconds(300))
        rig.expectNothingRan()
        #expect(!rig.toolsListenerStarted)

        // Allowed again, as after the profile is removed or a restart under an ordinary policy:
        // what was concluded stays concluded.
        let restarted = try PolicyRig(.unrestricted, root: rig.root)
        restarted.core.start()
        try await Task.sleep(for: .milliseconds(300))
        #expect(try restarted.core.store.unfinishedTurns().isEmpty)
        #expect(restarted.core.sessions[session]?.record.isQueuePaused == true)
        #expect(restarted.spawns == 0)
        restarted.stop()
        _ = previous
    }

    @Test("Clients can't widen the policy: the owner, a fully granted device and unknown methods are all refused")
    func clientsCannotWiden() async throws {
        let rig = try PolicyRig(Self.restricted, updater: PolicyUpdater(probe: PolicyProbe()))
        rig.core.start()
        let project = rig.root.appending(path: "project").path(percentEncoded: false)
        for grants in [ClientGrants.owner, Self.pairedDevice] {
            let client = try await rig.connect(grants)
            // A catalog entry is kept, whatever it claims; it never makes the agent launchable.
            try await client.syncAgents([rig.agentSpec(env: ["NATIVE_HOST_POLICY": "ordinary"])])

            for denied in [
                { _ = try await client.startAgent("fake") },
                { _ = try await client.newSession(NewSessionParams(agentID: "fake", cwd: project)) },
                { _ = try await RemoteCommandRunner(client: client).run(Command("/bin/echo", [], environment: [:])) },
                { _ = try await client.addProject(project, create: true) },
                { _ = try await client.setPluginEnabled("any", true) },
                { _ = try await client.checkForUpdate() },
                { _ = try await client.installUpdate(.now) },
            ] as [@Sendable () async throws -> Void] {
                let error = await #expect(throws: (any Error).self) { try await denied() }
                // Commands come back through the runner as refused, with the host's words.
                let rpc = error as? RPCError
                #expect(rpc.map { HostErrorCode($0) == .notAuthorized } ?? true)
                #expect((rpc?.message ?? error?.localizedDescription)?.contains("organization's policy") == true)
            }
            // Choosing who serves Native's tools (the Mac app's call) is a record; it starts no listener.
            if grants.isLocal { try await client.configureTasks(ConfigureTasksParams(servesTools: true)) }
            // What lets a denied host explain itself still works.
            _ = try await client.hostStatus()
            _ = try await client.sessions()
            _ = try await client.agents()
            #expect(try await client.updateStatus().state == .unavailable)
            let doctor = try await client.doctor()
            #expect(doctor.checks.map(\.id) == ["host.policy", "host.keepAwake", "host.updates"])
            #expect(
                doctor.checks.first?.detail == "It's a restricted deployment. Allowed here: pair or connect devices")
            await client.stop()
        }
        // A method this host doesn't know, as from a newer or forged client, is refused before its params.
        let unknown = await #expect(throws: RPCError.self) {
            _ = try await rig.request("_native/future/do_anything", grants: .owner)
        }
        #expect(unknown.flatMap { HostErrorCode($0) } == .notAuthorized)
        try await Task.sleep(for: .milliseconds(200))
        rig.expectNothingRan()
        #expect(!rig.toolsListenerStarted)
        rig.stop()
    }

    @Test("An ordinary host answers unknown methods as before")
    func unknownMethodInOrdinaryMode() async throws {
        let rig = try PolicyRig(.unrestricted)
        rig.core.start()
        let unknown = await #expect(throws: RPCError.self) {
            _ = try await rig.request("_native/future/do_anything", grants: .owner)
        }
        #expect(unknown?.code == RPCError.methodNotFound("").code)
        rig.stop()
    }

    @Test("A host whose policy turns updates off never checks in the background, and starts when allowed")
    func backgroundUpdates() async throws {
        let probe = PolicyProbe()
        var ordinaryWithoutUpdates = Set(HostCapability.allCases)
        ordinaryWithoutUpdates.remove(.updates)
        for denied in [Self.restricted, HostPolicy(mode: .ordinary, capabilities: ordinaryWithoutUpdates)] {
            let rig = try PolicyRig(denied, updater: PolicyUpdater(probe: probe))
            rig.core.start()
            try await Task.sleep(for: .milliseconds(300))
            #expect(probe.updateChecks == 0)
            let client = try await rig.connect(.owner)
            #expect(try await client.updateStatus().canInstall == false)
            await client.stop()
            rig.stop()
        }

        let rig = try PolicyRig(Self.restricted, updater: PolicyUpdater(probe: probe))
        rig.core.start()
        rig.policy.set(.unrestricted)
        try await rig.waitUntil("a background check") { probe.updateChecks > 0 }
        rig.stop()
    }

    @Test("Revoking agents ends the running turn, the agent and its queue's turn, and a restart doesn't revive it")
    func revokedRunningTurn() async throws {
        let rig = try PolicyRig(.unrestricted)
        rig.core.start()
        let client = try await rig.connect(.owner)
        try await client.syncAgents([rig.agentSpec()])
        let project = rig.root.appending(path: "project").path(percentEncoded: false)
        try FileManager.default.createDirectory(atPath: project, withIntermediateDirectories: true)
        let summary = try await client.newSession(NewSessionParams(agentID: "fake", cwd: project))
        _ = try await client.prompt(PromptParams(sessionID: summary.id, requestID: UUID(), text: "slow 100"))
        _ = try await client.prompt(
            PromptParams(sessionID: summary.id, requestID: UUID(), text: "next", behavior: .queue))
        try await rig.waitUntil("the turn to reach the agent") { rig.agentReceived.contains("prompt\tslow 100") }
        #expect(rig.spawns == 1)

        rig.policy.set(Self.restricted)
        rig.core.refreshPolicy()

        let session = try #require(rig.core.sessions[summary.id])
        #expect(session.turn == nil)
        #expect(session.record.isQueuePaused)
        #expect(session.queue.count == 1)
        #expect(try rig.core.store.unfinishedTurns().isEmpty)
        #expect(rig.core.agents["fake"]?.processIdentifier == nil)
        let failure = try rig.core.store.activity(after: nil, limit: 50).last { $0.kind == .turnFailed }
        #expect(failure?.detail?.contains("organization's policy") == true)
        await client.stop()

        let restarted = try PolicyRig(.unrestricted, root: rig.root)
        restarted.core.start()
        try await Task.sleep(for: .milliseconds(300))
        #expect(try restarted.core.store.unfinishedTurns().isEmpty)
        #expect(restarted.spawns == 1, "nothing started again on its own")
        restarted.stop()
        rig.stop()
    }

    @Test(
        "A launch revoked while its environment is read never spawns, even once allowed again",
        arguments: [false, true])
    func revokedInFlightLaunch(allowedAgain: Bool) async throws {
        let shell = PolicyGate()
        let rig = try PolicyRig(.unrestricted, shell: shell)
        rig.core.start()
        rig.core.syncAgentsForTests([rig.agentSpec()])
        let starting = Task { @HostActor in try await rig.core.readyAgent("fake") }
        try await rig.waitUntil("the environment to be read") { rig.probe.shellReads == 1 }

        rig.policy.set(Self.restricted)
        rig.core.refreshPolicy()
        if allowedAgain {
            rig.policy.set(.unrestricted)
            rig.core.refreshPolicy()
        }
        shell.open()

        await #expect(throws: (any Error).self) { _ = try await starting.value }
        try await Task.sleep(for: .milliseconds(200))
        #expect(rig.spawns == 0)
        rig.stop()
    }

    @Test("A turn committed while agents are denied, as a task handing another a message would, ends with the reason")
    func turnCommittedWhileDenied() async throws {
        let previous = try PolicyRig(.unrestricted)
        let id = try previous.seedSession()
        let rig = try PolicyRig(Self.restricted, root: previous.root)
        rig.core.start()
        let session = try #require(rig.core.sessions[id])

        try rig.core.startTurn(in: session, prompt: OutgoingPrompt(text: "from another task"))

        try await rig.waitUntil("the turn to end") { session.turn == nil }
        #expect(try rig.core.store.unfinishedTurns().isEmpty)
        #expect(session.record.isQueuePaused)
        let failure = try rig.core.store.activity(after: nil, limit: 50).last { $0.kind == .turnFailed }
        #expect(failure?.detail?.contains("organization's policy") == true)
        rig.expectNothingRan()
        _ = previous
    }

    @Test("A command revoked while it runs is cancelled")
    func revokedInFlightCommand() async throws {
        let rig = try PolicyRig(.unrestricted, holdsCommands: true)
        rig.core.start()
        let client = try await rig.connect(.owner)
        let project = rig.root.appending(path: "project").path(percentEncoded: false)
        _ = try await client.addProject(project, create: true)
        let running = Task {
            try await RemoteCommandRunner(client: client).run(
                Command("/bin/sleep", ["60"], in: project, environment: [:]))
        }
        try await rig.waitUntil("the command to start") { rig.probe.commands == 1 }

        rig.policy.set(Self.restricted)
        rig.core.refreshPolicy()

        await #expect(throws: (any Error).self) { _ = try await running.value }
        #expect(rig.probe.cancelledCommands == 1)
        await client.stop()
        rig.stop()
    }

    @Test("An update check revoked mid-way offers and installs nothing")
    func revokedInFlightUpdate() async throws {
        let gate = PolicyGate()
        let probe = PolicyProbe()
        let updater = PolicyUpdater(probe: probe, gate: gate)
        let rig = try PolicyRig(.unrestricted, updater: updater, checkInterval: .seconds(3600))
        rig.core.start()
        let client = try await rig.connect(.owner)
        _ = try await client.checkForUpdate()
        try await rig.waitUntil("the check to start") { probe.updateChecks == 1 }

        rig.policy.set(Self.restricted)
        rig.core.refreshPolicy()
        gate.open()
        try await Task.sleep(for: .milliseconds(200))

        let status = try await client.updateStatus()
        #expect(status.available == nil)
        #expect(status.state == .unavailable)
        await #expect(throws: RPCError.self) { _ = try await client.installUpdate(.now) }
        #expect(updater.activated.withLock { $0 }.isEmpty)
        #expect(rig.exits.values.isEmpty)
        await client.stop()
        rig.stop()
    }

    @Test("A blocked policy denies everything with side effects and says why; observers hear each change")
    func blockedPolicy() async throws {
        let rig = try PolicyRig(.unrestricted)
        let heard = Recorded<HostPolicy.Mode>()
        rig.core.observePolicy { heard.append($0.mode) }
        rig.core.start()
        let blocked = HostPolicy.blocked("Its managed policy couldn't be read.")
        rig.policy.set(blocked)
        try await rig.waitUntil("the refresh") { rig.core.policy == blocked }
        #expect(heard.values == [.blocked])
        #expect(blocked.capabilities.isEmpty)

        let client = try await rig.connect(.owner)
        try await client.syncAgents([rig.agentSpec()])
        let error = await #expect(throws: RPCError.self) { _ = try await client.startAgent("fake") }
        #expect(
            error?.message
                == "Your organization's policy doesn't allow this host to start agents. Its managed policy couldn't be read."
        )
        await client.stop()
        rig.expectNothingRan()
        rig.stop()
    }

    @Test("An agent outside the organization's list doesn't recover at startup, and others are unaffected")
    func disallowedAgentAtStartup() async throws {
        let previous = try PolicyRig(.unrestricted)
        let session = try previous.seedInterruptedTurn()
        let rig = try PolicyRig(Self.onlyOther, root: previous.root)
        rig.core.start()

        #expect(try rig.core.store.unfinishedTurns().isEmpty)
        #expect(rig.core.sessions[session]?.record.isQueuePaused == true)
        let recovery = try rig.core.store.activity(after: nil, limit: 50).compactMap(\.recovery).first
        #expect(recovery?.problem?.contains("doesn't allow this host to start Fake Agent") == true)
        try await Task.sleep(for: .milliseconds(300))
        #expect(rig.spawns == 0)
        _ = previous
    }

    @Test("Narrowing the organization's agent list ends the agents taken off it, and only those")
    func narrowedAgentList() async throws {
        let rig = try PolicyRig(.unrestricted)
        rig.core.start()
        let client = try await rig.connect(.owner)
        try await client.syncAgents([rig.agentSpec(), rig.agentSpec(id: "other")])
        #expect(try await client.startAgent("other").state == .ready)
        let project = rig.root.appending(path: "project").path(percentEncoded: false)
        try FileManager.default.createDirectory(atPath: project, withIntermediateDirectories: true)
        let summary = try await client.newSession(NewSessionParams(agentID: "fake", cwd: project))
        _ = try await client.prompt(PromptParams(sessionID: summary.id, requestID: UUID(), text: "slow 100"))
        try await rig.waitUntil("the turn to reach the agent") { rig.agentReceived.contains("prompt\tslow 100") }

        rig.policy.set(Self.onlyOther)
        rig.core.refreshPolicy()

        #expect(rig.core.sessions[summary.id]?.turn == nil)
        #expect(rig.core.agents["fake"]?.processIdentifier == nil)
        #expect(rig.core.agents["other"]?.processIdentifier != nil, "an allowed agent keeps running")
        // Starting it again answers with its state rather than an error, and starts nothing.
        let spawned = rig.spawns
        #expect(try await client.startAgent("fake").state != .ready)
        #expect(rig.spawns == spawned)
        let error = await #expect(throws: RPCError.self) {
            _ = try await client.newSession(NewSessionParams(agentID: "fake", cwd: project))
        }
        #expect(error?.message.contains("doesn't allow this host to start Fake Agent") == true)
        await client.stop()
        rig.stop()
    }

    @Test("Revoking only Native's tools stops their listener and their URLs while agents keep running")
    func revokedAgentTools() async throws {
        guard HostTasks.canServe else { return }
        let rig = try PolicyRig(.unrestricted)
        rig.core.start()
        let client = try await rig.connect(.owner)
        try await client.syncAgents([rig.agentSpec()])
        let project = rig.root.appending(path: "project").path(percentEncoded: false)
        try FileManager.default.createDirectory(atPath: project, withIntermediateDirectories: true)
        let summary = try await client.newSession(NewSessionParams(agentID: "fake", cwd: project))
        let served = await rig.core.tasks.agentServers(for: summary.id, base: [])
        let url = try #require(served.first?["url"]?.stringValue.flatMap(URL.init(string:)))
        #expect(rig.core.tasks.admittedCaller(of: summary.id.rawValue) != nil)

        var withoutTools = Set(HostCapability.allCases)
        withoutTools.remove(.agentTools)
        rig.policy.set(HostPolicy(mode: .ordinary, capabilities: withoutTools))
        rig.core.refreshPolicy()

        #expect(await rig.core.tasks.agentServers(for: summary.id, base: []).isEmpty)
        #expect(rig.core.tasks.admittedCaller(of: summary.id.rawValue) == nil)
        var request = URLRequest(url: url, timeoutInterval: 2)
        request.httpMethod = "POST"
        await #expect(throws: (any Error).self, "nothing listens at the tools' address") {
            _ = try await URLSession.shared.data(for: request)
        }
        #expect(rig.core.agents["fake"]?.processIdentifier != nil, "agents are still allowed")
        await client.stop()
        rig.stop()
    }

    @Test("A doctor check revoked while it reads the login shell runs nothing")
    func revokedInFlightDoctor() async throws {
        let open = try PolicyRig(.unrestricted)
        let report = try await open.connect(.owner).doctor()
        #expect(open.probe.commands > 0, "allowed, the checks run tools")
        #expect(!report.checks.contains { $0.id == "host.policy" })

        let shell = PolicyGate()
        let rig = try PolicyRig(.unrestricted, shell: shell)
        let client = try await rig.connect(.owner)
        let checking = Task { try await client.doctor() }
        try await rig.waitUntil("the environment to be read") { rig.probe.shellReads == 1 }

        rig.policy.set(.blocked("Its managed policy can't be read."))
        rig.core.refreshPolicy()
        shell.open()

        let blocked = try await checking.value
        #expect(blocked.checks.first?.id == "host.policy")
        #expect(rig.probe.commands == 0)
        await client.stop()
    }

    @Test("Restricted mode keeps only what's qualified for it, whatever the policy asks for")
    func restrictedKeepsOnlyQualified() {
        #expect(Self.restricted.capabilities == HostCapability.qualifiedWhenRestricted)
        #expect(!Self.restricted.allows(.agents))
        #expect(!Self.restricted.allows(.loginShell))
        #expect(!Self.restricted.allows(.updates))
    }

    @Test("Ordinary hosts work as before: agents start, commands run, the login shell is read")
    func ordinaryCompatibility() async throws {
        let rig = try PolicyRig(.unrestricted)
        #expect(rig.core.policy == .unrestricted)
        rig.core.start()
        let client = try await rig.connect(.owner)
        try await client.syncAgents([rig.agentSpec()])
        #expect(try await client.startAgent("fake").state == .ready)
        #expect(rig.spawns == 1)
        let project = rig.root.appending(path: "project").path(percentEncoded: false)
        _ = try await client.addProject(project, create: true)
        _ = try await RemoteCommandRunner(client: client).run(Command("/bin/echo", [], in: project, environment: [:]))
        #expect(rig.probe.commands == 1)
        #expect(rig.probe.shellReads == 1)
        if HostTasks.canServe {
            try await rig.waitUntil("Native's tools to listen") { rig.toolsListenerStarted }
        }
        await client.stop()
        rig.stop()
    }

    @Test("Linux has no managed source: a deployment file blocks the host, its absence leaves it unmanaged")
    func linuxDeploymentFile() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "host-policy-\(UUID().uuidString)")
        #expect(LinuxHostPolicySource(file: file).current() == .unrestricted)
        try Data().write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(LinuxHostPolicySource(file: file).current().mode == .blocked)
    }

    @Test("Every method is classified, and only status, reading and stopping go through whatever the policy")
    func admissionMap() {
        typealias Method = HostProtocol.Method
        #expect(HostMethodAdmission(Method.hostStatus) == .always)
        #expect(HostMethodAdmission(Method.cancel) == .always)
        #expect(HostMethodAdmission(Method.execCancel) == .always)
        #expect(HostMethodAdmission(Method.prompt) == .needs(.agents))
        #expect(HostMethodAdmission(Method.execRun) == .needs(.commands))
        #expect(HostMethodAdmission(Method.fsRead) == .needs(.files))
        #expect(HostMethodAdmission(Method.updateInstall) == .needs(.updates))
        #expect(HostMethodAdmission("_native/exec/something_new") == .unknown)
    }
}
