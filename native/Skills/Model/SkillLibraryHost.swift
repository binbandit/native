#if canImport(Skills)
import Foundation
import NativeOrchestration
import Skills

/// What the Skills feature needs from the app, so it depends on this rather than on the app
/// model's internals. `AppSkillsHost` provides it for `AppModel`.
protocol SkillLibraryHost: AnyObject {
    /// The agents Native runs that keep skills, in plugin order.
    var skillAgents: [SkillsAgent] { get }
    /// The open projects, whose own skills are listed.
    var skillProjects: [URL] { get }
    /// The user's login-shell environment on the host (`HOME`, `CODEX_HOME`, git's `PATH`).
    func skillEnvironment() async -> [String: String]
    /// Native's own skills, which its MCP tools serve every agent.
    var nativeSkills: [NativeSkillListing] { get }
    /// Agents still running with skill switches older than the current ones.
    var skillAgentsAwaitingRestart: [SkillsAgent] { get }
    /// Restarts those agents: only idle ones, unless `force`.
    func skillApplyLaunchPolicies(force: Bool) async
}

/// An agent whose skills Native lists, and how far a switch reaches it.
struct SkillsAgent: Identifiable, Hashable {
    let id: AgentDefinition.ID
    let definition: AgentDefinition
    let format: SkillAgentFormat
    /// From the agent plugin's policy translator.
    let switching: SkillSwitching

    var name: String { definition.displayName }
}

/// One of Native's own skills, as the Skills page lists it.
struct NativeSkillListing: Identifiable, Hashable {
    let id: String
    let title: String
    let summary: String
    /// The plugin that serves it, and whether that plugin is on (agents only see it then).
    let pluginName: String
    let isServed: Bool
}

/// `AppModel` as the Skills feature's host.
final class AppSkillsHost: SkillLibraryHost {
    /// Weak because the model owns the plugins, which own the library, which holds this.
    private weak var model: AppModel?

    init(model: AppModel) {
        self.model = model
    }

    var skillAgents: [SkillsAgent] {
        (model?.agents ?? []).compactMap { runtime in
            agent(runtime.agent)
        }
    }

    private func agent(_ definition: AgentDefinition) -> SkillsAgent? {
        // Until manifests declare their skills format (like `mcpConfig`), the built-in agents'
        // ids are their formats.
        guard let format = SkillAgentFormat(rawValue: definition.id.rawValue) else { return nil }
        let switching: SkillSwitching =
            switch model?.plugins.policyTranslator(for: definition.id)?.support(for: .skills) {
            case .perSession: .perSession
            case .atLaunch: .perProcess
            case .unsupported, nil: .unsupported
            }
        return SkillsAgent(id: definition.id, definition: definition, format: format, switching: switching)
    }

    var skillProjects: [URL] {
        model?.projects.all.map(\.url) ?? []
    }

    func skillEnvironment() async -> [String: String] {
        await model?.shellEnvironment() ?? [:]
    }

    var nativeSkills: [NativeSkillListing] {
        let isServed = model?.plugins.isEnabled("orchestration") ?? false
        return NativeSkill.bundled().map {
            NativeSkillListing(
                id: $0.id, title: $0.title, summary: $0.summary, pluginName: "Orchestration", isServed: isServed)
        }
    }

    var skillAgentsAwaitingRestart: [SkillsAgent] {
        (model?.agentsWithPendingLaunchPolicy ?? []).compactMap { agent($0.agent) }
    }

    func skillApplyLaunchPolicies(force: Bool) async {
        await model?.applyLaunchPolicies(force: force)
    }
}
#endif
