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
    var configuredAgent: AgentDefinition.ID?
    var options: [ConfigOption] = []
    var defaults: [String: String] = [:]
    var choices: [String: String] = [:]
    var workspace: TaskWorkspaceChoice?
    var workspaces: [TaskWorkspaceOption] = []
    var isReadingWorkspaces = false
    var workspaceRead = UUID()
    var workspaceFailure: String?
    var showsWorkspaces = false
    var isHeld = false
    var pendingAttachments = false
    var heldDraft: ComposeHeldDraft?
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
    #endif

    var hasContent: Bool {
        guard let editor else { return false }
        return !editor.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !editor.attachments.isEmpty
    }

    func choose(_ setting: SelectSetting, value: String) {
        guard !isHeld, stage == .writing, setting.choices.contains(where: { $0.value == value }),
            !PolicyPermissionModes.forbids(setting.option, value: value),
            let category = setting.option.category
        else { return }
        choices[category] = value == defaults[category] ? nil : value
        if let index = options.firstIndex(where: { $0.id == setting.option.id }) {
            options[index].kind = .select(currentValue: value, options: setting.choices)
        }
    }
}
