import NativeCommands

extension CommandID {
    static let taskCompareVersions: Self = "task.compareVersions"
    static let taskKeepVersion: Self = "task.keepVersion"
}

extension NativeCommand {
    /// Compare and Keep for a brief sent to two agents, on the selected task.
    static func taskPairs(model: AppModel) -> [NativeCommand] {
        [
            NativeCommand(
                .taskCompareVersions, title: "Compare Versions", category: .tasks,
                systemImage: "rectangle.split.2x1", keywords: ["two agents", "side by side"]
            ) { _ in
                guard let key = model.selection else { return }
                if model.comparedTaskPair(for: key) != nil {
                    model.closeTaskPairComparison()
                } else {
                    model.compareTaskPair(containing: key)
                }
            }
            .menuTitle { _ in
                model.selection.flatMap(model.comparedTaskPair(for:)) == nil ? "Compare Versions" : "Stop Comparing"
            }
            .available { _ in
                model.selection.flatMap(model.openTaskPair(containing:)).map(model.isTaskPairSettled) == true
            }
            .shownInSettings { model.offersTaskPairs },

            NativeCommand(
                .taskKeepVersion, title: "Keep This Version", category: .tasks, systemImage: "checkmark.circle",
                keywords: ["two agents", "choose"]
            ) { context in
                guard let key = model.selection else { return }
                Task { await model.keepTaskPairVersion(key, undoManager: context.undoManager) }
            }
            .available { _ in
                model.selection.flatMap(model.openTaskPair(containing:)).map(model.isTaskPairSettled) == true
            }
            .shownInSettings { model.offersTaskPairs },
        ]
    }
}
