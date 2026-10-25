import NativeCommands
import SwiftUI

extension CommandID {
    static let taskPeek: Self = "task.peek"
    static let taskAnswerOldestAsk: Self = "task.answerOldestAsk"
    static let taskShowNeedsYou: Self = "task.showNeedsYou"
}

extension NativeCommand {
    static func taskPeek(model: AppModel) -> [NativeCommand] {
        [
            NativeCommand(
                .taskShowNeedsYou, title: "Tasks Needing You", category: .tasks, systemImage: "square.grid.3x3"
            ) { $0.taskAttentionList?.wrappedValue = true }
            .available {
                model.offersTaskPeek && $0.taskAttentionList != nil
                    && !model.tasksNeedingAttention.isEmpty
            }
            .shownInSettings { model.offersTaskPeek },
            NativeCommand(.taskPeek, title: "Peek", category: .tasks, systemImage: "eye") { _ in
                if let key = model.selection { model.peekTask(key) }
            }.available { _ in model.offersTaskPeek && model.selection != nil }
                .shownInSettings { model.offersTaskPeek },
            NativeCommand(.taskAnswerOldestAsk, title: "Answer Oldest Ask", category: .tasks, systemImage: "checkmark")
            { _ in
                Task { await model.answerOldestTaskAsk() }
            }.available { _ in
                model.offersTaskPeek && model.answerShortcutAsk != nil && !model.taskPeek.isAnswering
            }
            .shownInSettings { model.offersTaskPeek },
        ]
    }
}

extension AppModel {
    func legacyAskShortcutEnabled(in registry: CommandRegistry) -> Bool {
        guard let shortcut = DefaultShortcuts.all[.taskAnswerOldestAsk],
            registry.bindings.commands(boundTo: shortcut) == [.taskAnswerOldestAsk]
        else { return false }
        return !offersTaskPeek || answerShortcutAsk == nil
    }
}
