import ACP
import Foundation
import MCPClient
import NativePolicy
import Observation
import Skills
import TaskDefaults

/// Preflight uses already available library data. Opening Settings never probes a server, signs in,
/// starts a task, or asks an agent for a report.
@Observable
final class NewTasksLoadsModel {
    private(set) var instructions: [TaskInstructionFile] = []
    private(set) var isReading = false
    private(set) var didRead = false
    let agent: AgentManifest
    let project: Project?
    let mcp: MCPLibrary?
    let skills: SkillLibrary?
    /// The agent as it launches, with its plugin's and the organization's environment, so the
    /// instruction folders it names (`HOME`, `CODEX_HOME`) are the ones it reads.
    private let definition: AgentDefinition
    private let launchEnvironment: [String: String]

    init(agent: AgentManifest, project: Project?, registry: PluginRegistry) {
        self.agent = agent
        self.project = project
        mcp = registry.isEnabled(MCPServersPlugin.id) ? MCPServersPlugin.library(in: registry) : nil
        skills = registry.isEnabled(SkillsPlugin.id) ? SkillsPlugin.library(in: registry) : nil
        let id = AgentDefinition.ID(rawValue: agent.id)
        definition = registry.agent(id) ?? AgentDefinition(agent, pluginID: "")
        launchEnvironment = registry.launchEnvironment(for: id)
    }

    /// Lists the instruction files the agent would read, launched from `shellEnvironment` as
    /// `AppModel.start` launches it. Only their sizes are read, never their text.
    func readInstructions(shellEnvironment: [String: String]) async {
        isReading = true
        let environment = definition.command(environment: shellEnvironment.merging(launchEnvironment) { $1 })
            .environment
        let home = environment["HOME"].map { URL(filePath: $0) } ?? FileManager.default.homeDirectoryForCurrentUser
        let files = await Task.detached {
            [locations = definition.manifest.instructionLocations, project = project?.url] in
            TaskInstructionInventory.read(locations, home: home, project: project, environment: environment)
        }.value
        guard !Task.isCancelled else { return }
        instructions = files
        didRead = true
        isReading = false
    }

    var instructionItems: [NewTasksLoadItem] {
        instructions.map { file in
            NewTasksLoadItem(
                id: file.id.absoluteString, name: file.url.lastPathComponent,
                source: file.scope == .project ? project?.name ?? "Project" : "\(agent.name)'s own",
                kind: .instructions, tokens: file.bytes.map(TaskContextBudget.estimate),
                loadedBy: file.scope == .project ? agent.name : nil)
        }
    }

    /// The glyph for a load row's source, as `SettingsSourceLabel` draws the same sources.
    func symbol(forSource source: String, policy: NativePolicy) -> String? {
        switch source {
        case "\(agent.name)'s own": "doc"
        case project?.name: "folder"
        case policy.organizationDisplayName: "building.2"
        default: nil
        }
    }

    func serverItems(policy: NativePolicy) -> [NewTasksLoadItem] {
        guard let mcp else { return [] }
        let id = AgentDefinition.ID(rawValue: agent.id)
        let format = agent.mcpConfig.flatMap(AgentConfigFormat.init)
        let own = format.map { mcp.agentServers($0, in: project?.url) } ?? []
        let target = ManagedServerDelivery.Target(
            agentID: agent.id, directory: project?.url,
            transports: mcp.agents.first { $0.id == id }?.transports,
            agentServers: own, switches: mcp.switches)
        let managed = ManagedServerDelivery.plan(mcp.servers, for: target).filter {
            $0.server.agents.includes(agent.id) && $0.server.includes(directory: project?.url)
        }
        var result = own.map { configured in
            let policyLocked = !policy.mcp.allows(configured.server)
            let required = configured.scope == .managed
            let selected = mcp.mode(of: configured.server.endpoint.key, in: project?.url)
            let source =
                policyLocked || required
                ? policy.organizationDisplayName
                : configured.scope.project != nil ? project?.name ?? "Project" : "\(agent.name)'s own"
            let support = mcp.host?.mcpPolicySupport(for: id)
            let canSwitch: Bool =
                switch support {
                case .perSession?: true
                case .atLaunch?: project == nil
                default: false
                }
            var item = serverItem(
                key: .agent(configured.id), name: configured.name, source: source,
                included: configured.status.isLoaded && selected == .on && !policyLocked,
                switchKey: configured.server.endpoint.key, canSwitch: canSwitch && !required && !policyLocked,
                policy: policy, policyDecision: policyLocked ? "Blocked" : required ? "Required" : nil)
            if required { item.control = .required }
            if policyLocked {
                item.control = .unavailable(
                    "Not allowed by \(policy.organizationDisplayName). \(policy.organizationHelp)")
            }
            if configured.status != .enabled { item.detail = configured.status.inactiveReason }
            if selected == .scripted { item.detail = "Available through scripts; tool definitions load on demand." }
            if !canSwitch && !required && !policyLocked {
                item.detail = "\(agent.name) manages this server. Change it in Tools & Skills."
            }
            return item
        }
        for decision in managed {
            if case .alreadyLoaded = decision.outcome { continue }
            let server = decision.server
            // The transport identity suffices for policy matching; no secrets are requested here.
            let locked = !policy.mcp.allows(server.config(with: ManagedServerSecrets()))
            var item = serverItem(
                key: .managed(server.id), name: server.name, source: "Shared with every agent",
                included: decision.outcome.isDelivered && !locked, switchKey: server.transport.endpoint.key,
                canSwitch: !locked, policy: policy, policyDecision: locked ? "Blocked" : nil)
            if locked {
                item.control = .unavailable(
                    "Not allowed by \(policy.organizationDisplayName). \(policy.organizationHelp)")
            }
            if decision.outcome != .deliver { item.detail = decision.outcome.inactiveReason(agentName: agent.name) }
            result.append(item)
        }
        for server in policy.mcp.required where !result.contains(where: { $0.name == server.name }) {
            result.append(
                .init(
                    id: "required-\(server.name)", name: server.name, source: policy.organizationDisplayName,
                    kind: .tools, tokens: nil, control: .required,
                    detail: "Required by \(policy.organizationDisplayName). \(policy.organizationHelp)"))
        }
        return result
    }

    private func serverItem(
        key: MCPServerKey, name: String, source: String, included: Bool,
        switchKey: String, canSwitch: Bool, policy: NativePolicy, policyDecision: String? = nil
    ) -> NewTasksLoadItem {
        guard let mcp else { return .init(id: name, name: name, source: source, kind: .tools) }
        let report = mcp.reports[key]
        let cost = report.flatMap { $0.isConnected ? TaskContextBudget.estimate(bytes: $0.toolDefinitionBytes) : nil }
        let selected = mcp.mode(of: switchKey, in: project?.url) == .on
        var item = NewTasksLoadItem(
            id: String(describing: key), name: name, source: source, kind: .tools, tokens: cost,
            included: included, control: canSwitch ? .switchable(selected) : .agentOwned)
        if let report, !report.isConnected {
            // A probe is not the agent's authentication status. Never claim the agent will skip it.
            item.detail = "Couldn't connect at the last check. \(agent.name) may sign in itself."
            item.needsAttention = true
        }
        item.setEnabled = { [project] enabled in
            mcp.setMode(enabled ? .on : .off, of: switchKey, in: project?.url)
        }
        let local = project.flatMap { mcp.switches.explicitMode(of: switchKey, in: $0.url) }
        let global = mcp.switches.explicitMode(of: switchKey, in: nil)
        let locked = policyDecision != nil
        item.receipt = NewTasksSettingReceipt(
            title: name, context: "for \(agent.name)\(project.map { " in \($0.name)" } ?? " in all projects")",
            value: included ? "On" : "Not loaded directly",
            source: locked
                ? .organization(policy.organizationDisplayName)
                : local != nil ? .project(project?.name ?? "Project") : global != nil ? .user : .agent(agent.name),
            layers: [
                .init(
                    name: policy.organizationDisplayName, symbol: "building.2", value: policyDecision, wins: locked,
                    isOrganization: true),
                .init(
                    name: project?.name ?? "Project", symbol: "folder", value: local?.rawValue,
                    wins: !locked && local != nil, overridden: locked && local != nil),
                .init(
                    name: "You", symbol: "person", value: global?.rawValue,
                    wins: !locked && local == nil && global != nil,
                    overridden: (locked || local != nil) && global != nil),
                .init(
                    name: source, symbol: "doc", value: "Server configuration",
                    wins: !locked && local == nil && global == nil),
            ],
            note:
                "Project switches override All projects. The agent's configuration and transport support also determine whether it loads."
        )
        let previous = mcp.switches.explicitMode(of: switchKey, in: project?.url)
        item.undo = { [project] in mcp.setMode(previous, of: switchKey, in: project?.url) }
        item.reset = { [project] in mcp.setMode(nil, of: switchKey, in: project?.url) }
        return item
    }

    func skillItems(policy: NativePolicy) -> [NewTasksLoadItem] {
        guard let skills, let provider = skills.agents.first(where: { $0.id.rawValue == agent.id }) else { return [] }
        return skills.items.compactMap { item in
            let places = item.places.filter {
                $0.root.agents.contains(provider.format)
                    && ($0.root.scope.project == nil || $0.root.scope.project == project?.url)
            }
            // Errors and descriptions from another agent or project must not change this task's inventory.
            guard let item = SkillInventory.items(places).first, let place = item.places.first else { return nil }
            let locked = policy.blockedSkills.contains { $0.localizedCaseInsensitiveCompare(item.name) == .orderedSame }
            let on = skills.mode(of: item.key, in: project?.url) == .on && !locked
            let canSwitch =
                places.allSatisfy { provider.format.canSwitch($0.root.scope) }
                && (provider.switching != .perProcess || project == nil
                    || places.allSatisfy { $0.root.scope.project != nil })
            let description = place.document?.frontmatter.description ?? item.description ?? ""
            var row = NewTasksLoadItem(
                id: item.id, name: item.name,
                source: locked
                    ? policy.organizationDisplayName
                    : place.root.scope.project != nil
                        ? project?.name ?? "Project"
                        : place.root.scope == .user ? "Yours" : "\(agent.name)'s own",
                kind: .skills, tokens: TaskContextBudget.estimate(bytes: (item.name + description).utf8.count),
                included: on && !item.hasErrors,
                control: locked
                    ? .unavailable("Blocked by \(policy.organizationDisplayName). \(policy.organizationHelp)")
                    : canSwitch ? .switchable(on) : .agentOwned)
            if !canSwitch { row.detail = "\(agent.name) manages this skill at this scope." }
            if item.hasErrors {
                row.detail = "This skill couldn't be read. Review it in Tools & Skills."; row.needsAttention = true
            }
            row.setEnabled = { [project] enabled in
                skills.setMode(enabled ? .on : .off, for: item.key, in: project?.url)
            }
            let local = project.flatMap { skills.switches.explicitMode(of: item.key, in: $0.url) }
            let global = skills.switches.explicitMode(of: item.key, in: nil)
            row.receipt = NewTasksSettingReceipt(
                title: item.name, context: "for \(agent.name)", value: on ? "On" : "Off",
                source: locked
                    ? .organization(policy.organizationDisplayName)
                    : local != nil ? .project(project?.name ?? "Project") : global != nil ? .user : .agent(agent.name),
                layers: [
                    .init(
                        name: policy.organizationDisplayName, symbol: "building.2", value: locked ? "Blocked" : nil,
                        wins: locked, isOrganization: true),
                    .init(
                        name: project?.name ?? "Project", symbol: "folder",
                        value: local?.rawValue, wins: !locked && local != nil, overridden: locked && local != nil),
                    .init(
                        name: "You", symbol: "person",
                        value: global?.rawValue, wins: !locked && local == nil && global != nil,
                        overridden: (locked || local != nil) && global != nil),
                    .init(
                        name: row.source, symbol: "doc", value: "Skill definition",
                        wins: !locked && local == nil && global == nil),
                ], note: "Project switches override All projects where the agent supports them.",
                help: locked ? policy.organizationHelp : nil)
            let previous = skills.switches.explicitMode(of: item.key, in: project?.url)
            row.undo = { [project] in skills.setMode(previous, for: item.key, in: project?.url) }
            row.reset = { [project] in skills.setMode(nil, for: item.key, in: project?.url) }
            return row
        }
    }
}
