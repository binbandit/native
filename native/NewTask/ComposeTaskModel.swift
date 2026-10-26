import ACP
import Foundation
import Observation

/// The page owns a local draft, never an agent conversation, until Start.
@Observable
final class ComposeTaskModel {
    enum Stage { case writing, folding, message, settled }

    var isPresented = false
    var editor: SessionModel?
    var stage = Stage.writing
    var starting: StartingTask?
    var navigationSelection: SessionKey?
    var configuredAgent: AgentDefinition.ID? {
        didSet { if oldValue != configuredAgent { permissionBeforePlan = nil } }
    }
    /// Part of the draft, so dismissing its picker cannot broaden permissions when leaving Plan.
    var permissionBeforePlan: String?
    var options: [ConfigOption] = []
    var defaults: [String: String] = [:]
    var choices: [String: String] = [:]
    var workspace: TaskWorkspaceChoice?
    var workspaces: [TaskWorkspaceOption] = []
    var isReadingWorkspaces = false
    var workspaceRead = UUID()
    var workspaceFailure: String?
    var showsWorkspaces = false
    var workspaceSelection: TaskWorkspaceChoice?
    var isHeld = false
    var pendingAttachments = false
    var heldDraft: ComposeHeldDraft?
    /// A second agent on the To line: the same brief goes to both, each in its own worktree.
    var second: ComposeRecipient?
    @ObservationIgnored private let storage: UserDefaults

    init(defaults: UserDefaults = .standard) {
        storage = defaults
        heldDraft = defaults.data(forKey: "compose.heldDraft")
            .flatMap { try? JSONDecoder().decode(ComposeHeldDraft.self, from: $0) }
        isHeld = heldDraft != nil
    }

    func hold(_ draft: ComposeHeldDraft) throws {
        storage.set(try JSONEncoder().encode(draft), forKey: "compose.heldDraft")
        heldDraft = draft
        isHeld = true
    }

    func cancelHold() {
        storage.removeObject(forKey: "compose.heldDraft")
        heldDraft = nil
        isHeld = false
    }
    #if DEBUG
    var previewBranch: String?
    var previewState: String?
    var previewLastConnected: Date?
    #endif

    var hasContent: Bool {
        guard let editor else { return false }
        return !editor.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !editor.attachments.isEmpty
    }

    var commandDraft: SessionModel? {
        isPresented && !isHeld && stage == .writing ? editor : nil
    }

    var addressedChoices: [String: String] { Self.addressedChoices(in: options) }

    /// The settings a task is started with, by category.
    static func addressedChoices(in options: [ConfigOption]) -> [String: String] {
        Dictionary(
            options.compactMap { option in
                guard let category = option.category, ["model", "thought_level", "mode"].contains(category),
                    case .select(let value, _) = option.kind
                else { return nil }
                return (category, value)
            }, uniquingKeysWith: { first, _ in first })
    }

    func beginWorkspaceSelection() {
        workspaceSelection = workspace
        showsWorkspaces = true
    }

    func cancelWorkspaceSelection() {
        workspaceSelection = nil
        showsWorkspaces = false
    }

    func applyWorkspaceSelection() {
        guard let workspaceSelection else { return }
        workspace = workspaceSelection
        cancelWorkspaceSelection()
    }

    func choose(_ setting: SelectSetting, value: String) {
        guard !isHeld, stage == .writing, setting.choices.contains(where: { $0.value == value }),
            !PolicyPermissionModes.forbids(setting.option, value: value),
            let category = setting.option.category
        else { return }
        if category == "mode" {
            if value == ComposerSettings.planValue {
                if setting.value != value, permissionBeforePlan == nil { permissionBeforePlan = setting.value }
            } else {
                permissionBeforePlan = nil
            }
        }
        choices[category] = value == defaults[category] ? nil : value
        if let index = options.firstIndex(where: { $0.id == setting.option.id }) {
            options[index].kind = .select(currentValue: value, options: setting.choices)
        }
    }

    func setPlanning(_ isPlanning: Bool) {
        guard let plan = ComposerSettings(options).plan, plan.isOn != isPlanning else { return }
        if isPlanning {
            choose(plan.setting, value: plan.plan.value)
        } else if let permission = permissionBeforePlan
            ?? defaults["mode"].flatMap({ $0 == ComposerSettings.planValue ? nil : $0 })
            ?? plan.setting.choices.first(where: { $0.value != plan.plan.value })?.value
        {
            choose(plan.setting, value: permission)
        }
    }

}

/// An agent the brief also goes to, with the settings its task starts with: the project's and the
/// agent's defaults, as a new task of its own would have.
struct ComposeRecipient: Equatable {
    let agent: AgentDefinition.ID
    var options: [ConfigOption]

    var modelName: String? { ComposerSettings(options).model?.currentName }
    var choices: [String: String] { ComposeTaskModel.addressedChoices(in: options) }
}
