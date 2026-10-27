import ACP
import Git
import NativeAutomation

/// Features contribute context through model callbacks; the handoff itself needs no model call.
enum ChangeAgentWiring {
    static func connect(model: AppModel, git: GitStore, automation: AutomationCenter) {
        model.agentChangeGoalBlock = { source in
            automation.goal(for: source)?.goal?.status == .active
                ? "Pause the task's goal before changing agents. Its goal text will be included in the handoff." : nil
        }
        model.modelChangeGoalBlock = { source in
            automation.goal(for: source)?.goal != nil
                ? "Clear this task's goal before choosing another agent. Its goal cannot move safely yet." : nil
        }
        model.changeAgentHandoff = { source in
            let repository = git.model(for: source.cwd, session: source.key)
            await repository.refreshNow()
            var paths = repository.changes.map(\.path)
            var note: String?
            switch repository.state {
            case .ready: note = nil
            case .notRepository: note = "This folder is not a Git repository; only reported edits are listed."
            case .loading, .failed: note = "Git changes could not be read; only reported edits are listed."
            }
            if let checkout = repository.repository,
                let base = try? await checkout.branchBase(),
                let snapshot = await GitTurnBaselines.snapshot(of: checkout),
                let changes = try? await checkout.treeChanges(from: base.commit, to: snapshot.tree)
            {
                paths += changes.flatMap(\.paths)
                note = "Includes branch changes since \(base.name); a shared branch may include other work."
            }
            return TaskHandoff.draft(
                title: source.displayTitle, state: source.state,
                objective: automation.goal(for: source)?.goal?.objective,
                changedPaths: paths, fileStatus: note)
        }
    }
}
