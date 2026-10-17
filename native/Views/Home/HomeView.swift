import SwiftUI

/// Home while there are projects and no task is selected: a card per agent that starts a task, the
/// project those tasks start in as the quiet link under the cards, and the latest tasks across
/// agents and projects below.
///
/// Everything comes in as values and goes out through the closures, so the app decides what the
/// actions do. The chosen project is a binding because ⌘N should start its task in the same
/// project the cards do.
public struct HomeView<AgentID: Hashable, ProjectID: Hashable, TaskID: Hashable>: View {
    /// Every agent, in the registry's order; each gets a card.
    let agents: [HomeAgent<AgentID>]
    let projects: [HomeProject<ProjectID>]
    /// The project new tasks start in.
    @Binding var project: ProjectID
    /// Recent tasks, most recent first: the chosen project's, or across projects, in which case rows
    /// name their project. The page lists the first few.
    let recentTasks: [HomeTask<TaskID>]
    let onNewTask: (AgentID, ProjectID) -> Void
    let onAddProject: () -> Void
    let onSelectTask: (TaskID) -> Void

    public init(
        agents: [HomeAgent<AgentID>],
        projects: [HomeProject<ProjectID>],
        project: Binding<ProjectID>,
        recentTasks: [HomeTask<TaskID>],
        onNewTask: @escaping (AgentID, ProjectID) -> Void,
        onAddProject: @escaping () -> Void,
        onSelectTask: @escaping (TaskID) -> Void
    ) {
        self.agents = agents
        self.projects = projects
        _project = project
        self.recentTasks = recentTasks
        self.onNewTask = onNewTask
        self.onAddProject = onAddProject
        self.onSelectTask = onSelectTask
    }

    public var body: some View {
        HomePage(hasActivity: !recentTasks.isEmpty) {
            ForEach(agents) { agent in
                HomeAgentCard(agent: agent, isBusy: isCreatingTask) {
                    onNewTask(agent.id, project)
                }
            }
        } footer: {
            HomeProjectMenu(projects: projects, selection: $project, onAddProject: onAddProject)
        } content: {
            if recentTasks.isEmpty {
                HomeNoTasks(projectName: projectName, agent: firstTaskAgent) { agent in
                    onNewTask(agent, project)
                }
                .padding(.top, HomeLayout.sectionSpacing)
            } else {
                HomeRecentTasks(
                    tasks: Array(recentTasks.prefix(HomeLayout.recentTaskLimit)),
                    totalCount: recentTasks.count,
                    onSelect: onSelectTask
                )
                .padding(.top, HomeLayout.sectionSpacing)
            }
        }
    }

    private var isCreatingTask: Bool {
        agents.contains { $0.availability == .creatingTask }
    }

    private var projectName: String {
        projects.first { $0.id == project }?.name ?? "this project"
    }

    /// The agent the empty list offers: the ⌘N agent when it's ready, else the first ready one.
    private var firstTaskAgent: HomeAgent<AgentID>? {
        let ready = agents.filter { $0.availability == .available }
        return ready.first { $0.shortcut != nil } ?? ready.first
    }
}
