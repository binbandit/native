#if DEBUG
import Experiments
import SwiftUI

struct StartingTaskPreviewFixture: View {
    let failed: Bool
    /// Fine print: the failure as Codex reports a value its config.toml doesn't allow.
    var finePrint = false
    @State private var app = AppModel.preview()
    @State private var experiments = ExperimentStore(catalog: .native, storage: InMemoryExperimentStorage())

    var body: some View {
        if let project = app.previewProject(), let agent = app.agents.first?.agent {
            let task = StartingTask(
                project: project.id, agent: agent, isAgentPicked: true, workspaceLabel: "Preparing the workspace")
            let _ = configure(task, folder: project.url)
            let _ = experiments.set(finePrint, for: .composerNext)
            StartingTaskView(task: task)
                .environment(app)
                .environment(\.experimentStore, experiments)
                .frame(width: finePrint ? 960 : 640, height: finePrint ? 640 : 480)
        }
    }

    private func configure(_ task: StartingTask, folder: URL) {
        task.folder = folder
        task.draft = "Check the changes and run the tests."
        task.wantsComposerFocus = false
        if failed, finePrint {
            task.isSendRequested = true
            task.failure = StartingTask.Failure(
                title: "Couldn't start a \(task.agent.displayName) task", message: AskPreviewFixtures.unknownEffort)
        } else if failed {
            task.failure = StartingTask.Failure(
                title: "Couldn't start \(task.agent.displayName)",
                message: "The agent stopped before initialization finished.", needsRestart: true)
        }
    }
}
#endif
