import ACP

/// Features contribute context through model callbacks; the handoff itself needs no model call.
enum ChangeAgentWiring {
    static func connect(model: AppModel, git: GitStore, automation: AutomationCenter) {
        model.agentChangeGoalBlock = { source in
            automation.goal(for: source)?.goal?.status == .active
                ? "Pause the task's goal before changing agents. Its goal text will be included in the handoff." : nil
        }
        model.changeAgentHandoff = { source in
            let repository = git.model(for: source.cwd, session: source.key)
            await repository.refreshNow()
            let note: String?
            switch repository.state {
            case .ready: note = nil
            case .notRepository: note = "This folder is not a Git repository; only reported edits are listed."
            case .loading, .failed: note = "Git changes could not be read; only reported edits are listed."
            }
            return TaskHandoff.draft(
                title: source.displayTitle, state: source.state,
                objective: automation.goal(for: source)?.goal?.objective,
                changedPaths: repository.changes.map(\.path), fileStatus: note)
        }
    }
}
