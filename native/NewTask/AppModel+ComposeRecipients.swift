import ACP
import Foundation
import NativePolicy

// A second agent on the Compose page's To line. Start makes one task per agent from the same brief,
// each in its own worktree, and groups them (TaskPairs) until the user keeps one.
extension AppModel {
    /// Agents the brief can also go to: allowed here, ready, and not already on the To line.
    var composeSecondAgentChoices: [AgentRuntime] {
        quickEntryRuntimes.filter { runtime in
            runtime.agent.id != quickEntry.agent && runtime.isAvailable && !runtime.needsSignIn
                && PolicyCenter.shared.policy.agents.allows(runtime.agent.id.rawValue)
        }
    }

    /// Two agents need two worktrees, so a second one is offered only where git can make them.
    var composeOffersSecondAgent: Bool {
        composeTask.workspaces.contains { $0.choice == .newWorktree }
    }

    var composeSecondRuntime: AgentRuntime? {
        guard let second = composeTask.second else { return nil }
        return quickEntryRuntimes.first { $0.agent.id == second.agent }
    }

    func addComposeAgent(_ agent: AgentDefinition.ID) {
        guard !composeTask.isHeld, composeTask.stage == .writing, agent != quickEntry.agent,
            composeOffersSecondAgent
        else { return }
        composeTask.second = ComposeRecipient(
            agent: agent, options: composeStartingOptions(for: agent, in: quickEntry.project.flatMap(projects.project)))
        composeTask.workspace = .newWorktree
        quickEntry.failure = nil
    }

    func removeComposeAgent() {
        guard !composeTask.isHeld, composeTask.stage == .writing else { return }
        composeTask.second = nil
        quickEntry.failure = nil
    }

    /// After the first agent, the project or the device changed, the second stays only while it's
    /// another agent this device has, with the new project's defaults.
    func reconcileComposeSecondAgent() {
        guard let second = composeTask.second else { return }
        guard second.agent != quickEntry.agent, quickEntryRuntimes.contains(where: { $0.agent.id == second.agent })
        else {
            composeTask.second = nil
            return
        }
        composeTask.second = ComposeRecipient(
            agent: second.agent,
            options: composeStartingOptions(for: second.agent, in: quickEntry.project.flatMap(projects.project)))
    }

    /// Why the second agent can't take the brief now, or nil when it can.
    func composeSecondAgentProblem() -> String? {
        guard let second = composeTask.second else { return nil }
        let name = plugins.agent(second.agent)?.displayName ?? second.agent.rawValue
        guard let runtime = composeSecondRuntime, runtime.isAvailable, !runtime.needsSignIn,
            PolicyCenter.shared.policy.agents.allows(second.agent.rawValue)
        else { return "\(name) can't take the task right now. Remove it from To, or start when it's ready." }
        guard composeTask.workspace == .newWorktree else {
            return
                "Two agents each need a worktree of their own, and this folder can't make one. Remove \(name) to start."
        }
        return nil
    }

    /// Lists the brief's second task beside `first`, with the same message and attachments, and
    /// groups the two. Starting it is the caller's, once both share a starting commit.
    func listComposeSecondTask(beside first: StartingTask) -> StartingTask? {
        guard let second = composeTask.second, let runtime = composeSecondRuntime else { return nil }
        let task = StartingTask(
            project: first.project, agent: runtime.agent, isAgentPicked: false, workspaceLabel: "Creating a worktree")
        task.device = first.device
        task.workspaceChoice = .newWorktree
        task.draft = first.draft
        task.attachments = first.attachments
        task.configChoices = second.choices
        task.usesComposePresentation = true
        task.isSendRequested = true
        task.wantsComposerFocus = false
        startingTasks.insert(task, at: min(1, startingTasks.count))
        taskPairs.add([first.id, task.id])
        return task
    }

    /// Chooses one commit for every task of a brief still waiting for its worktree, so their
    /// versions differ only by the agents' work; the pair keeps it as the base to compare from.
    /// When no commit can be chosen, every waiting task fails with the reason rather than starting
    /// on its own, and Retry chooses again for both. Returns whether they can start.
    @discardableResult
    func pinSharedWorktreeStart(for tasks: [StartingTask]) async -> Bool {
        let waiting = tasks.filter { $0.workspaceChoice == .newWorktree && $0.folder == nil }
        guard let first = tasks.first, !waiting.isEmpty else { return true }
        do {
            guard let project = projects.project(first.project) else { throw TaskPairStartFailure.noProject }
            let start: TaskWorkspaceChoice?
            switch first.device {
            case .thisMac:
                start = try await taskWorkspaces?.newWorktreeStart(in: project)
            case .remote(let id):
                guard let host = hosts.host(id), let path = project.checkoutPath(on: first.device),
                    let provider = await taskWorkspaces(on: host)
                else { throw TaskPairStartFailure.noCheckout }
                start = try await provider.newWorktreeStart(in: project.onHost(at: path))
            }
            guard let start, case .newWorktreeFrom(let commit, _, _) = start else {
                throw TaskPairStartFailure.noWorktrees
            }
            for task in waiting { task.workspaceChoice = start }
            taskPairs.setStart(commit, forPairContaining: first.id)
            return true
        } catch {
            for task in waiting {
                fail(
                    task, "Couldn't choose one starting point for both tasks",
                    "\(error.localizedDescription.withoutTerminalEscapes) Retry chooses again for both.")
            }
            return false
        }
    }

    /// Escape before the first task opened takes back both of the brief's tasks.
    func discardComposePartner(of task: StartingTask) {
        guard let pair = taskPairs.pair(containing: task.id), let other = pair.other(than: task.id),
            let partner = startingTask(other), partner.openedSession == nil
        else { return }
        discard(partner)
    }
}

/// Why a brief's tasks couldn't be given one starting commit.
enum TaskPairStartFailure: LocalizedError {
    case noProject, noCheckout, noWorktrees

    var errorDescription: String? {
        switch self {
        case .noProject: "The project isn't in Native any more."
        case .noCheckout: "The device doesn't have the project checked out."
        case .noWorktrees: "This folder can't make worktrees."
        }
    }
}
