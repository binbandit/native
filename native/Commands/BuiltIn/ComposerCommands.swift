import ACP
import Experiments
import NativeCommands
import SwiftUI

extension CommandID {
    static let composerFocus: Self = "composer.focus"
    static let composerAttachFiles: Self = "composer.attachFiles"
    static let sessionStop: Self = "session.stop"
    static let sessionNextPermissionMode: Self = "session.nextPermissionMode"
    static let sessionChooseModel: Self = "session.chooseModel"
    static let sessionChangeWorkspace: Self = "session.changeWorkspace"
}

extension NativeCommand {
    /// The visible task's composer and its agent's settings.
    static let composer: [NativeCommand] = [
        NativeCommand(
            .sessionChangeWorkspace, title: "Change Workspace…", category: .tasks, systemImage: "arrow.triangle.branch",
            keywords: ["branch", "worktree", "folder"]
        ) { $0.session?.requestWorkspaceChange() }
        .available { $0.session?.canChangeWorkspace == true },

        NativeCommand(.composerFocus, title: "Focus Composer", category: .composer, systemImage: "text.cursor") {
            if let instruction = $0.taskPeekInstructionFocus {
                instruction.wrappedValue = true
            } else {
                $0.session?.wantsComposerFocus = true
            }
        }
        .available { $0.taskPeekInstructionFocus != nil || ($0.session.map { !$0.isSubagent } ?? false) },

        NativeCommand(
            .composerAttachFiles, title: "Attach Files…", category: .composer, systemImage: "paperclip",
            keywords: ["image", "upload"]
        ) {
            $0.session?.isAttachmentPickerRequested = true
        }
        .available { context in
            guard let session = context.session else { return false }
            return session.acceptsPrompts && session.phase != .disconnected
        },

        NativeCommand(
            .sessionStop, title: "Stop", category: .composer, systemImage: "stop.circle", keywords: ["cancel", "turn"]
        ) { context in
            Task { await context.session?.cancel() }
        }
        .available { $0.session?.canCancel == true },

        NativeCommand(
            .sessionNextPermissionMode, title: "Next Permission Mode", category: .composer, systemImage: "lock.shield",
            keywords: ["autonomy", "approvals"]
        ) { context in
            guard let session = context.session else { return }
            Task { await nextPermissionMode(of: session) }
        }
        .available { context in
            context.session.map { ComposerSettings($0.configOptions).autonomy != nil } ?? false
        },

        NativeCommand(.sessionChooseModel, title: "Choose Model…", category: .composer, systemImage: "cpu") {
            $0.session?.isModelPickerRequested = true
        }
        .available { context in
            context.session.map {
                ExperimentStore.shared.value(of: .composerNext) || ComposerSettings($0.configOptions).model != nil
            } ?? false
        },
    ]

    /// Moves the permission mode one step up the autonomy scale, wrapping around; Plan Mode isn't a step.
    private static func nextPermissionMode(of session: SessionModel) async {
        guard let change = ComposerSettings(session.state.configOptions).nextAutonomy else { return }
        await session.setConfigOption(change.setting.option, to: change.value)
    }
}
