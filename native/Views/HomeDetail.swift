import ACP
import SwiftUI

/// The detail pane while no session is selected: the home page of the current project, or the
/// welcome page before any project is open. Wires the Home feature to the app model.
struct HomeDetail: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let project = model.currentProject {
            HomeView(
                folder: project.url,
                agents: model.agents.map(homeAgent),
                recentTasks: model.sessions(in: project.id).map(homeTask),
                recentFolders: model.projects.all.map(\.url),
                onNewTask: { agent in Task { await model.newSession(in: project.id, with: agent) } },
                onOpenFolder: { model.isAddingProject = true },
                onOpenRecent: { url in Task { await model.addProject(url) } },
                onSelectTask: { model.selection = $0 }
            )
        } else {
            HomeWelcomeView(
                recentFolders: [],
                openFolderShortcut: KeyboardShortcut("o"),
                onOpenFolder: { model.isAddingProject = true },
                onOpenRecent: { url in Task { await model.addProject(url) } }
            )
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
            date: model.session(summary.id)?.lastActivity ?? summary.info.updatedDate
        )
    }
}
