import SwiftUI
import TaskScripts

/// Runs the script being edited once, in a scratch worktree of a project (removed afterwards) or in
/// the current task's folder, and shows how it went as it runs.
struct TaskScriptTestPanel: View {
    let text: String
    let target: TaskScriptEditorSheet.Target

    @Environment(TaskScriptCenter.self) private var center
    @Environment(AppModel.self) private var model
    @State private var run: TaskScriptRun?
    @State private var place = Place.scratchWorktree
    @State private var chosenProject: URL?

    enum Place: Hashable {
        case scratchWorktree, currentTask
    }

    /// The selected task's folder, where "The current task" runs it.
    private var currentTask: URL? {
        model.selection.flatMap(model.session)?.cwd
    }

    /// The project a scratch worktree is made of: the script's own, or for a global script the one
    /// picked, the current task's by default.
    private var project: URL? {
        target.scope.project ?? chosenProject ?? model.currentProject?.url ?? model.projects.all.first?.url
    }

    private var testTarget: TaskScriptCenter.TestTarget? {
        switch place {
        case .scratchWorktree: project.map { .scratchWorktree(project: $0) }
        case .currentTask: currentTask.map { .task(folder: $0) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack(spacing: DS.Space.md) {
                Text("Test in")
                    .settingsText(.body)
                    .foregroundStyle(.dsTextSecondary)
                Picker("Test in", selection: $place) {
                    Text("A scratch worktree").tag(Place.scratchWorktree)
                    Text("The current task").tag(Place.currentTask)
                }
                .labelsHidden()
                .fixedSize()
                if place == .scratchWorktree, target.scope == .global, !model.projects.all.isEmpty {
                    Picker("Of", selection: Binding(get: { project }, set: { chosenProject = $0 })) {
                        ForEach(model.projects.all) { project in
                            Text("of \(project.name)").tag(Optional(project.url))
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                Spacer()
                if let run, run.isRunning {
                    Button("Stop") { center.stop(run) }
                        .buttonStyle(.ds(.secondary))
                } else {
                    Button("Run Test") {
                        guard let testTarget else { return }
                        run = center.test(text, source: source, event: target.event, in: testTarget)
                    }
                    .buttonStyle(.ds(.secondary))
                    .disabled(testTarget == nil || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            Text(placeNote)
                .settingsText(.caption)
                .foregroundStyle(.dsTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let run {
                status(run)
                TaskScriptOutputView(output: run.output, maxHeight: TaskScriptMetrics.logOutputMaxHeight)
            }
        }
    }

    private var source: TaskScript.Source {
        switch target.scope {
        case .global: .global
        case .project: .project
        case .repository: .repository
        }
    }

    private var placeNote: String {
        switch place {
        case .scratchWorktree:
            guard let project else { return "Add a project to test in a scratch worktree of it." }
            return
                "Native makes a worktree of \(project.lastPathComponent) with its env files, runs the script there with the variables a task gets, then removes it."
        case .currentTask:
            guard let currentTask else { return "Open a task to test the script in its folder." }
            return "Runs for real in \(currentTask.abbreviatedPath), with the task's variables."
        }
    }

    @ViewBuilder private func status(_ run: TaskScriptRun) -> some View {
        HStack(spacing: DS.Space.sm) {
            switch run.state {
            case .running, .awaitingApproval:
                DotGridLoader(pattern: .settingUp)
                    .foregroundStyle(.dsTextSecondary)
                    .frame(width: TaskScriptMetrics.loader, height: TaskScriptMetrics.loader)
                Text("Running")
                ElapsedTimeText(since: run.startedAt)
            case .succeeded, .skipped:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.dsSuccess)
                Text("Finished in \(DSFormat.duration(run.duration ?? 0))")
            case .failed(let failure):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.dsDanger)
                Text("It \(failure.result.outcome.phrase) after \(DSFormat.duration(run.duration ?? 0))")
            }
        }
        .settingsText(.body)
        .foregroundStyle(.dsTextPrimary)
    }
}
