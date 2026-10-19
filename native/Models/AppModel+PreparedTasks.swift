import ACP
import Foundation

// Tasks whose checkout was made before they started, by a feature rather than the task workspace
// provider: a pull request opened as a task runs in a worktree of its head.
extension AppModel {
    enum PreparedTaskError: LocalizedError {
        case noAgent
        case agentUnavailable(String)

        var errorDescription: String? {
            switch self {
            case .noAgent: "No agent is installed to start the task with."
            case .agentUnavailable(let reason): reason
            }
        }
    }

    /// Starts a task in `project` that runs in `folder`, with `agent` or the project's agent and
    /// model (or the defaults), lists it in the sidebar under the project, titles it and selects it.
    /// When the agent wants a sign-in, its sign-in prompt shows too.
    func startTask(
        in project: Project.ID, folder: URL, title: String?, agent requested: AgentDefinition.ID? = nil
    ) async throws -> SessionModel {
        if requested == nil, defaultAgent(in: projects.project(project)) == nil {
            await agentsChecked()
        }
        guard let agent = requested ?? defaultAgent(in: projects.project(project))?.id else {
            // Add Agent says how to get one.
            isAddingAgent = true
            throw PreparedTaskError.noAgent
        }
        guard let runtime = await ensureRunning(agent) else {
            throw PreparedTaskError.agentUnavailable(startFailure(of: agent))
        }
        do {
            let session = try await launcher.start(on: runtime, cwd: folder, project: project)
            catalog.add(
                SessionInfo(sessionId: session.id, cwd: folder.folderPath, updatedAt: .now), for: agent, in: project)
            if let title {
                rename(session.key, to: title)
            }
            session.wantsComposerFocus = true
            selection = session.key
            return session
        } catch {
            if runtime.noteSignInRequired(by: error), !runtime.authMethods.isEmpty {
                signInPrompt = agent
            }
            throw SessionLauncher.LaunchError.failed(agent: runtime.agent.displayName, underlying: error)
        }
    }
}
