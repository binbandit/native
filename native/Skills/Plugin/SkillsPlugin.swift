#if canImport(Skills)
import ACP
import Foundation

#if canImport(AppKit)
import AppKit
#endif

/// One switch per skill across every agent: lists the skills agents load (theirs, the project's,
/// their plugins' and Native's own), contributes the ones switched off to each session's policy,
/// and installs, updates and removes skills from Settings ▸ Skills.
struct SkillsPlugin: NativePlugin {
    static let id = "skills"

    let manifest = PluginManifest(
        id: Self.id,
        name: "Skills",
        description:
            "Lists the skills your agents load, turns them on and off for every agent at once, and installs new ones."
    )

    /// One for the app: the settings page and this plugin read the same skills and switches.
    let library = SkillLibrary()

    func sessionPolicy(for session: SessionContext) -> SessionPolicy {
        library.sessionPolicy(for: session)
    }

    func launchPolicy(for agent: AgentDefinition.ID) -> SessionPolicy {
        library.launchPolicy(for: agent)
    }
}

extension SkillsPlugin {
    /// Points the library at the app and reads every skill before agents launch, since those that
    /// apply switches at launch need them.
    static func connect(to model: AppModel) {
        guard let library = library(in: model.plugins) else { return }
        library.host = AppSkillsHost(model: model)
        library.readAtStartup()
        Task {
            await library.read()
            await library.host?.skillApplyLaunchPolicies(force: false)
        }
        // Skills change outside Native (an agent writes one, a pull updates one); coming back to
        // the app is when that matters.
        #if canImport(AppKit)
        _ = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in await library.readIfStale() }
        }
        #endif
    }

    static func library(in registry: PluginRegistry) -> SkillLibrary? {
        registry.plugins.lazy.compactMap { ($0.plugin as? SkillsPlugin)?.library }.first
    }
}
#endif
