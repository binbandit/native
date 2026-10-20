#if DEBUG
import ACP
import Modes
import SwiftUI

/// What a composer direction gets from `ComposerView`: the session, what the composer knows right now,
/// and its actions. Directions only arrange these; every action is today's.
struct ComposerDirectionParts {
    typealias Prompt = SessionModel.QueuedPrompt

    let session: SessionModel
    let settings: ComposerSettings
    let mode: TaskModeControl
    let suggestions: ComposerSuggestions?
    @Binding var highlighted: Int
    let changedFiles: Set<String>
    /// What Return does with a follow-up while the agent works.
    let followUp: FollowUpBehavior
    let followUpHint: FollowUpHint?
    let hasContent: Bool
    let isWorking: Bool
    let canEdit: Bool
    let isFocused: Bool
    let resumedAutonomy: String?
    let sendBlockedReason: String?
    let isDropTargeted: Bool
    @Binding var isModelPickerOpen: Bool
    @Binding var isPickingFiles: Bool

    let submit: (FollowUpBehavior) -> Void
    let stop: () -> Void
    let set: (SelectSetting, String) -> Void
    let sendNow: (Prompt.ID) -> Void
    let edit: (Prompt) -> Void
    let remove: (Prompt.ID) -> Void
    let chooseCommand: (ComposerSlashCommand) -> Void
    let chooseFile: (String, FileMentionQuery) -> Void
    /// Writes the draft and puts the caret at its end, focused: B's settings write their command.
    let write: (String) -> Void
    /// Applies a setting's value (a model, an effort level, a mode) and says so.
    let applyChoice: (CommandLineChoice) -> Void

    var agentName: String { session.agentName }

    /// Send's glyph: send, or while the agent works, steer or queue as Return would.
    var sendKind: DirectionRoundButton.Kind {
        .send(followUp: followUp, isWorking: session.canCancel, supportsSteering: session.supportsSteering)
    }

    /// The oldest tool call waiting for the user's approval.
    var approval: ToolCallState? {
        session.permissionRequests.first
    }

    func answer(_ option: PermissionOption, for call: ToolCallState) {
        Task { await session.choose(option, forToolCall: call.id) }
    }

    /// The short name of the model, as the controls show it.
    var modelName: String? {
        settings.model?.shortModelName
    }

    var effortName: String? {
        settings.effort.map(\.currentName)
    }

    var autonomyName: String? {
        let levels = settings.autonomyLevels
        guard !levels.isEmpty else { return nil }
        return levels[min(settings.shownAutonomyLevel(resumed: resumedAutonomy), levels.count - 1)].name
    }
}
#endif
