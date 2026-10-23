#if DEBUG
import SwiftUI

struct StartingTaskPreviewFixture: View {
    let failed: Bool
    @State private var app = AppModel.preview()

    var body: some View {
        if let project = app.previewProject(), let agent = app.agents.first?.agent {
            let task = StartingTask(
                project: project.id, agent: agent, isAgentPicked: true, workspaceLabel: "Preparing the workspace")
            let _ = configure(task, folder: project.url)
            StartingTaskView(task: task)
                .environment(app)
                .frame(width: 640, height: 480)
        }
    }

    private func configure(_ task: StartingTask, folder: URL) {
        task.folder = folder
        task.draft = "Check the changes and run the tests."
        task.wantsComposerFocus = false
        if failed {
            task.failure = StartingTask.Failure(
                title: "Couldn't start \(task.agent.displayName)",
                message: "The agent stopped before initialization finished.", needsRestart: true)
        }
    }
}
#endif
