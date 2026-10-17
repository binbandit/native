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
                onNewTask: { agent, project in Task { await model.newSession(in: project, with: agent) } },
                onAddProject: { model.isAddingProject = true },
                onSelectTask: { model.selection = $0 }
            )
        } else {
            HomeWelcomeView(agents: agents, addProjectShortcut: KeyboardShortcut("o"), onAddProject: { model.isAddingProject = true })
        }
    }

    private func homeAgent(_ runtime: AgentRuntime) -> HomeAgent<AgentDefinition.ID> {
        HomeAgent(
            id: runtime.agent.id,
            name: runtime.agent.displayName,
            symbolName: runtime.agent.symbolName,
            availability: availability(of: runtime),
            shortcut: runtime.agent.id == model.defaultAgent?.id ? KeyboardShortcut("n") : nil
        )
    }

    private func availability(of runtime: AgentRuntime) -> HomeAgent<AgentDefinition.ID>.Availability {
        if model.creatingSessionWith == runtime.agent.id { return .creatingTask }
        return switch runtime.status {
        case .starting: .starting
        case .ready where runtime.needsSignIn: .unavailable("Needs sign-in")
        case .ready: .available
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
