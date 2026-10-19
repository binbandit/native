import NativeCommands
import ProjectActions
import SwiftUI

extension CommandID {
    static let projectActionsRunLast: Self = "projectActions.runLast"
    static let projectActionsStop: Self = "projectActions.stop"
    static let projectActionsEdit: Self = "projectActions.edit"

    /// "Run: <name>": one command per action name, so a shortcut given to "Run: Test" runs Test in
    /// whichever project is in view.
    static func projectActionsRun(_ key: String) -> Self {
        Self("projectActions.run.\(key)")
    }

    var isProjectActionRun: Bool {
        rawValue.hasPrefix("projectActions.run.")
    }
}

extension NativeCommand {
    /// Run Last (⇧⌘R), Stop and Edit Project Actions…, for the task in the frontmost window. Their
    /// keys are in `docs/keyboard.md`, Project actions.
    static func projectActions(
        _ runner: ProjectActionRunner, target: @escaping @MainActor (CommandContext) -> ProjectActionTarget?
    ) -> [NativeCommand] {
        [
            NativeCommand(
                .projectActionsRunLast, title: "Run Last Action", category: .actions, systemImage: "arrow.clockwise",
                keywords: ["again", "rerun", "repeat"]
            ) { context in
                guard let target = target(context) else { return }
                runner.runLast(in: target)
            }
            .menuTitle { context in
                target(context).flatMap { runner.store.lastRunAction(in: $0.project) }.map { "Run Last: \($0.name)" }
                    ?? "Run Last Action"
            }
            .available { context in
                target(context).map { runner.store.lastRunAction(in: $0.project) != nil } ?? false
            },

            NativeCommand(
                .projectActionsStop, title: "Stop Action", category: .actions, systemImage: "stop.fill",
                keywords: ["cancel", "interrupt", "kill"]
            ) { context in
                guard let target = target(context) else { return }
                for action in runner.running(in: target) {
                    runner.stop(action, in: target)
                }
            }
            .menuTitle { context in
                guard let target = target(context) else { return "Stop Action" }
                let running = runner.running(in: target)
                return running.count == 1 ? "Stop \(running[0].name)" : "Stop Action"
            }
            .available { context in
                target(context).map { !runner.running(in: $0).isEmpty } ?? false
            },

            NativeCommand(
                .projectActionsEdit, title: "Edit Project Actions…", category: .actions,
                systemImage: "slider.horizontal.3", keywords: ["add", "scripts", "commands"]
            ) { context in
                guard let target = target(context) else { return }
                runner.hooks.editActions(target.project)
            }
            .available { target($0) != nil },
        ]
    }

    /// "Run: <name>" for each action name, running that action in the task in view when its project
    /// has one by that name.
    static func projectActionRuns(
        named names: [String], runner: ProjectActionRunner,
        target: @escaping @MainActor (CommandContext) -> ProjectActionTarget?
    ) -> [NativeCommand] {
        var seen: Set<String> = []
        return names.compactMap { name -> NativeCommand? in
            guard let key = ProjectAction.key(forName: name), seen.insert(key).inserted else { return nil }
            @MainActor func action(_ context: CommandContext) -> (ProjectAction, ProjectActionTarget)? {
                guard let target = target(context),
                    let action = runner.store.list(for: target.project).all.first(where: { $0.key == key })
                else { return nil }
                return (action, target)
            }
            return NativeCommand(
                .projectActionsRun(key), title: "Run: \(name)", category: .actions, systemImage: "play",
                keywords: ["action", "script"]
            ) { context in
                guard let (action, target) = action(context) else { return }
                runner.run(action, in: target)
            }
            .menuTitle { action($0).map(\.0.name) ?? name }
            .available { action($0) != nil }
        }
    }
}

/// The menu bar's Run menu: Run Last, Stop, the project's actions (each with the shortcut the user
/// gave it), and Edit Project Actions….
struct ProjectActionCommands: Commands {
    let runner: ProjectActionRunner
    let commands: CommandRegistry
    let target: @MainActor (SessionModel) -> ProjectActionTarget?
    @FocusedValue(\.activeSession) private var session

    var body: some Commands {
        CommandMenu("Run") {
            CommandMenuItem(.projectActionsRunLast, in: commands)
            CommandMenuItem(.projectActionsStop, in: commands)
            if let target = session.flatMap(target) {
                let actions = runner.store.list(for: target.project).all
                if !actions.isEmpty {
                    Divider()
                    ForEach(Self.keyed(actions), id: \.self) { key in
                        CommandMenuItem(.projectActionsRun(key), in: commands)
                    }
                }
            }
            Divider()
            CommandMenuItem(.projectActionsEdit, in: commands)
        }
    }

    /// The actions' command keys, once each, in the project's order.
    private static func keyed(_ actions: [ProjectAction]) -> [String] {
        var seen: Set<String> = []
        return actions.compactMap(\.key).filter { seen.insert($0).inserted }
    }
}
