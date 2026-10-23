import NativeCommands

extension CommandID {
    static let taskPeek: Self = "task.peek"
    static let taskAnswerOldestAsk: Self = "task.answerOldestAsk"
}

extension NativeCommand {
    static func taskPeek(model: AppModel) -> [NativeCommand] {
        [
            NativeCommand(.taskPeek, title: "Peek", category: .tasks, systemImage: "eye") { _ in
                if let key = model.selection { model.peekTask(key) }
            }.available { _ in model.offersTaskPeek && model.selection != nil }
                .shownInSettings { model.offersTaskPeek },
            NativeCommand(.taskAnswerOldestAsk, title: "Answer Oldest Ask", category: .tasks, systemImage: "checkmark")
            { _ in
                Task { await model.answerOldestTaskAsk() }
            }.available { _ in model.offersTaskPeek && model.oldestTaskAsk != nil && !model.taskPeek.isAnswering }
                .shownInSettings { model.offersTaskPeek },
        ]
    }
}
