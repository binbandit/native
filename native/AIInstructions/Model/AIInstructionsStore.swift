import AIInstructions
import Foundation
import NativePolicy
import Observation

/// The user's own instructions for what Native writes with AI: global ones, each project's own
/// (which replace the global ones for a purpose), and the organization's (which replace both and
/// lock Settings). Every feature that builds a prompt asks it for the purpose's addition.
@MainActor
@Observable
final class AIInstructionsStore {
    static let shared = AIInstructionsStore()

    /// The user's instructions for each purpose, everywhere.
    private(set) var global: [AIInstructionPurpose: String] {
        didSet { defaults.set(AIInstructionSettings.propertyList(global), forKey: Self.globalKey) }
    }
    /// Projects' own instructions, by `AIInstructionProject.key(for:)` of the project folder.
    private(set) var projects: [String: [AIInstructionPurpose: String]] {
        didSet { defaults.set(projects.mapValues(AIInstructionSettings.propertyList), forKey: Self.projectsKey) }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let policy: PolicyCenter

    private static let globalKey = "aiInstructions.global"
    private static let projectsKey = "aiInstructions.projects"

    init(defaults: UserDefaults = .standard, policy: PolicyCenter = .shared) {
        self.defaults = defaults
        self.policy = policy
        global = AIInstructionSettings.purposes(defaults.dictionary(forKey: Self.globalKey) as? [String: String] ?? [:])
        let stored = defaults.dictionary(forKey: Self.projectsKey) as? [String: [String: String]] ?? [:]
        projects = stored.mapValues(AIInstructionSettings.purposes)
    }

    /// The organization's instructions, while it manages them.
    var managed: [AIInstructionPurpose: String]? {
        guard policy.isManaged(.aiInstructions) else { return nil }
        return AIInstructionSettings.purposes(policy.policy.aiInstructions ?? [:])
    }

    var settings: AIInstructionSettings {
        AIInstructionSettings(global: global, projects: projects, managed: managed)
    }

    /// What to add to `purpose`'s prompt for work in `folder` (a project, a folder in one, or a
    /// task's worktree of one); nil folder gets the global instructions.
    func addition(for purpose: AIInstructionPurpose, in folder: URL?) -> AIInstructionAddition? {
        settings.addition(for: purpose, in: folder)
    }

    // MARK: - Global

    /// The global text for `purpose`, or the organization's while it manages them.
    func text(for purpose: AIInstructionPurpose) -> String {
        managed.map { $0[purpose] ?? "" } ?? global[purpose] ?? ""
    }

    func setText(_ text: String, for purpose: AIInstructionPurpose) {
        global[purpose] = text.isEmpty ? nil : String(text.prefix(AIInstructionAddition.maximumLength))
    }

    // MARK: - Projects

    /// The project's own text for `purpose`, or nil while it uses the global instructions.
    func projectText(for purpose: AIInstructionPurpose, in project: URL) -> String? {
        projects[AIInstructionProject.key(for: project)]?[purpose]
    }

    /// Gives the project its own text for `purpose` (empty means none), or nil to use the global
    /// instructions again.
    func setProjectText(_ text: String?, for purpose: AIInstructionPurpose, in project: URL) {
        let key = AIInstructionProject.key(for: project)
        var own = projects[key] ?? [:]
        own[purpose] = text.map { String($0.prefix(AIInstructionAddition.maximumLength)) }
        projects[key] = own.isEmpty ? nil : own
    }

    /// The projects with their own text for `purpose`, by folder name, for showing where the
    /// global instructions don't apply.
    func projectNames(overriding purpose: AIInstructionPurpose) -> [String] {
        projects.filter { $0.value[purpose] != nil }.keys
            .map { URL(filePath: $0, directoryHint: .isDirectory).lastPathComponent }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
