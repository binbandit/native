import ACP
import SwiftUI

/// The detail pane while no session is selected: the home page, which starts tasks in any project
/// and lists the latest ones, or the welcome page before any project is open. Wires the Home
/// feature to the app model.
struct HomeDetail: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let agents = model.agents.map(homeAgent)
        if let current = model.currentProject {
            HomeView(
                agents: agents,
                projects: model.projects.all.map { HomeProject(id: $0.id, name: $0.name, url: $0.url) },
                project: Binding(get: { model.currentProject?.id ?? current.id }, set: { model.focusProject($0) }),
                recentTasks: model.sessionList.sorted { lastActive($0) > lastActive($1) }.map(homeTask),
                waitingTasks: waitingTasks,
                onNewTask: { agent, project in Task { await model.newSession(in: project, with: agent) } },
                onAddProject: { model.isAddingProject = true },
                onSelectTask: { model.selection = $0 }
            )
        } else {
            HomeWelcomeView(
                agents: agents, addProjectShortcut: KeyboardShortcut("o"),
                onAddProject: { model.isAddingProject = true })
        }
    }

    private func homeAgent(_ runtime: AgentRuntime) -> HomeAgent<AgentDefinition.ID> {
        HomeAgent(
            id: runtime.agent.id,
            name: runtime.agent.displayName,
            symbolName: runtime.agent.symbolName,
            availability: availability(of: runtime),
            remedy: remedy(for: runtime),
            shortcut: runtime.agent.id == model.defaultAgent?.id ? KeyboardShortcut("n") : nil
        )
    }

    /// The one action that makes an agent that can't start tasks able to again.
    private func remedy(for runtime: AgentRuntime) -> HomeAgentRemedy? {
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

    /// Tasks waiting on the user, the longest-waiting first.
    private var waitingTasks: [HomeWaitingTask<SessionKey>] {
        model.sessionList
            .compactMap { summary -> (SessionSummary, SessionModel, SessionWait)? in
                guard let session = model.session(summary.id), let wait = session.wait else { return nil }
                return (summary, session, wait)
            }
            .sorted { ($0.1.lastActivity ?? .distantPast) < ($1.1.lastActivity ?? .distantPast) }
            .map { summary, _, wait in
                let (request, status): (String, TaskStatus) =
                    switch wait {
                    case .input(let question): (question, .needsInput)
                    case .permission(let tool): (tool, .needsPermission)
                    case .planReview(let plan): (plan, .needsPlanReview)
                    }
                return HomeWaitingTask(
                    id: summary.id, title: model.title(for: summary), request: request, status: status,
                    agentName: summary.agent.displayName)
            }
    }

    private func availability(of runtime: AgentRuntime) -> HomeAgent<AgentDefinition.ID>.Availability {
        if model.creatingSessionWith == runtime.agent.id { return .creatingTask }
        return switch runtime.status {
        case .starting: .starting
        case .ready where runtime.needsSignIn: .unavailable("Needs sign-in")
        // An idle agent starts when the user picks it.
        case .idle, .ready: .available
        case .notInstalled, .failed: .unavailable(runtime.status.label)
        }
    }

    private func homeTask(_ summary: SessionSummary) -> HomeTask<SessionKey> {
        HomeTask(
            id: summary.id,
            title: model.title(for: summary),
            agentName: summary.agent.displayName,
            agentSymbolName: summary.agent.symbolName,
            projectName: model.projects.project(summary.project)?.name ?? "",
            date: lastActivity(summary)
        )
    }

    private func lastActivity(_ summary: SessionSummary) -> Date? {
        model.session(summary.id)?.lastActivity ?? summary.info.updatedDate
    }

    private func lastActive(_ summary: SessionSummary) -> Date {
        lastActivity(summary) ?? .distantPast
    }
}
