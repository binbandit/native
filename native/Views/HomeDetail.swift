import ACP
import Experiments
import SwiftUI

/// The detail pane while no session is selected: the home page, which starts tasks in any project
/// and lists the latest ones, or the welcome page before any project is open. Wires the Home
/// feature to the app model.
struct HomeDetail: View {
    @Environment(AppModel.self) private var model
    @Environment(SettingsPresentation.self) private var settings
    @Experiment(.homeNext) private var homeNext

    var body: some View {
        let agents = model.agents.map(homeAgent)
        if model.taskGroups.isEmpty {
            NoProjectHome(agents: agents)
        } else if model.offersSidebarFolders, model.focusedProjectID != nil,
            model.currentProject.map({ model.allSessions(in: $0.id).isEmpty }) == true
        {
            SidebarFolderHome(agents: agents)
        } else if homeNext || model.currentProject == nil {
            next(agents: agents)
        } else if let current = model.currentProject {
            HomeView(
                agents: agents,
                projects: model.projects.all.map { HomeProject(id: $0.id, name: $0.name, url: $0.url) },
                project: Binding(get: { model.currentProject?.id ?? current.id }, set: { model.focusProject($0) }),
                recentTasks: model.sessionList.sorted { lastActive($0) > lastActive($1) }.map(homeTask),
                waitingTasks: waitingTasks,
                startupFailure: model.agentStartupFailure,
                onManageAgents: { settings.open(.agents) },
                onNewTask: { agent, project in Task { await model.newSession(in: project, with: agent) } },
                onAddProject: { model.isAddingProject = true },
                onSelectTask: { model.selection = $0 }
            )
        } else {
            NoProjectHome(agents: agents)
        }
    }

    @ViewBuilder private func next(agents: [HomeAgent<AgentDefinition.ID>]) -> some View {
        #if DEBUG
        if let fixture = HomeNextPreviewFixtures.requested {
            HomeNextFixtureView(state: fixture)
        } else {
            nextLive(agents: agents)
        }
        #else
        nextLive(agents: agents)
        #endif
    }

    private func nextLive(agents: [HomeAgent<AgentDefinition.ID>]) -> some View {
        HomeNextView(
            agents: agents,
            isLoading: model.projects.all.contains { model.isFindingSessions(in: $0.id) })
    }

    private func homeAgent(_ runtime: AgentRuntime) -> HomeAgent<AgentDefinition.ID> {
        var agent = HomeAgent(
            id: runtime.agent.id,
            name: runtime.agent.displayName,
            symbolName: runtime.agent.symbolName,
            availability: availability(of: runtime),
            remedy: remedy(for: runtime),
            shortcut: runtime.agent.id == model.defaultAgent(in: model.currentProject)?.id
                ? CommandRegistry.shared.keyboardShortcut(for: .sessionNew) : nil
        )
        agent.agent = runtime.agent
        return agent
    }

    /// The one action that makes an agent that can't start tasks able to again.
    private func remedy(for runtime: AgentRuntime) -> HomeAgentRemedy? {
        if let missingFolder {
            return HomeAgentRemedy("Look for the Folder Again") { Task { await model.retry(missingFolder) } }
        }
        let agent = runtime.agent
        switch runtime.status {
        case .notInstalled:
            return HomeAgentRemedy("Check Again for \(agent.displayName)") { Task { await model.restart(agent.id) } }
        case .failed:
            return HomeAgentRemedy("Restart \(agent.displayName)") { Task { await model.restart(agent.id) } }
        case .ready where runtime.needsSignIn && !runtime.authMethods.isEmpty:
            return HomeAgentRemedy("Sign In to \(agent.displayName)") { model.signInPrompt = agent.id }
        case .idle, .starting, .ready:
            return nil
        }
    }

    /// The chosen project's folder is gone, so no agent can start a task there until it's back.
    private var missingFolder: ProjectProblem? {
        model.currentProject.flatMap { model.missingFolder(of: $0.id) }
    }

    /// Tasks waiting on the user, the longest-waiting first.
    private var waitingTasks: [HomeWaitingTask<SessionKey>] {
        model.sessionList
            .compactMap { summary -> (SessionSummary, SessionModel, TaskStatus)? in
                guard let session = model.session(summary.id) else { return nil }
                // The status every surface reads, so Home lists exactly what the sidebar and the
                // status bar call "needs you".
                let status = session.taskStatus
                return status.needsAttention ? (summary, session, status) : nil
            }
            .sorted { ($0.1.lastActivity ?? .distantPast) < ($1.1.lastActivity ?? .distantPast) }
            .map { summary, session, status in
                // A subagent can say it's blocked before its request arrives; until then, the status.
                HomeWaitingTask(
                    id: summary.id, title: model.title(for: summary), request: session.wait?.summary ?? status.label,
                    status: status, agentName: summary.agent.displayName)
            }
    }

    private func availability(of runtime: AgentRuntime) -> HomeAgent<AgentDefinition.ID>.Availability {
        if missingFolder != nil { return .unavailable("Can't find the project's folder") }
        if model.creatingSessionWith == runtime.agent.id { return .creatingTask }
        return switch runtime.status {
        case .ready where runtime.needsSignIn: .unavailable("Needs sign-in")
        // A task picked while the agent is idle or still starting waits for it, showing as starting.
        case .idle, .starting, .ready: .available
        case .notInstalled, .failed: .unavailable(runtime.status.label)
        }
    }

    private func homeTask(_ summary: SessionSummary) -> HomeTask<SessionKey> {
        var task = HomeTask(
            id: summary.id,
            title: model.title(for: summary),
            agentName: summary.agent.displayName,
            agentSymbolName: summary.agent.symbolName,
            projectName: model.projects.project(summary.project)?.name ?? "",
            date: lastActivity(summary)
        )
        task.agent = summary.agent
        return task
    }

    private func lastActivity(_ summary: SessionSummary) -> Date? {
        model.lastActivity(for: summary)
    }

    private func lastActive(_ summary: SessionSummary) -> Date {
        lastActivity(summary) ?? .distantPast
    }
}

#if DEBUG
#Preview("Home detail - Next") { HomeNextPreviewFixtures.page(.busy) }
#endif
