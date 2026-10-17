import SwiftUI

/// Sample data for the home page's previews.
enum HomePreviewFixtures {
    static let projects: [HomeProject<String>] = [
        HomeProject(
            id: "native", name: "native",
            url: URL(filePath: "/Users/preview/Developer/native", directoryHint: .isDirectory)),
        HomeProject(
            id: "pier", name: "pier", url: URL(filePath: "/Users/preview/Developer/pier", directoryHint: .isDirectory)),
        HomeProject(
            id: "acp", name: "agent-client-protocol",
            url: URL(filePath: "/Users/preview/Developer/agent-client-protocol", directoryHint: .isDirectory)),
    ]

    static let agents: [HomeAgent<String>] = [
        HomeAgent(id: "claude-code", name: "Claude Code", symbolName: "asterisk", shortcut: KeyboardShortcut("n")),
        HomeAgent(id: "codex", name: "Codex", symbolName: "terminal"),
        HomeAgent(id: "cursor", name: "Cursor", symbolName: "cursorarrow", availability: .starting),
    ]

    /// Every way an agent can be unable to start a task.
    static let troubledAgents: [HomeAgent<String>] = [
        HomeAgent(
            id: "claude-code", name: "Claude Code", symbolName: "asterisk",
            availability: .unavailable("Limit reached · resets 3:05 PM")
        ),
        HomeAgent(
            id: "codex", name: "Codex", symbolName: "terminal",
            availability: .unavailable("Needs sign-in"), remedy: HomeAgentRemedy("Sign In to Codex") {}
        ),
        HomeAgent(
            id: "cursor", name: "Cursor", symbolName: "cursorarrow",
            availability: .unavailable("Not installed"), remedy: HomeAgentRemedy("Check Again for Cursor") {}
        ),
    ]

    static let tasks: [HomeTask<String>] = [
        task("1", "Queue follow-ups while a turn runs", agent: 0, project: 0, minutesAgo: 4),
        task("2", "Fix flaky permission request test", agent: 1, project: 0, minutesAgo: 52),
        task("3", "Landing page hero", agent: 2, project: 1, minutesAgo: 3 * 60),
        task("4", "Session titles from the first prompt", agent: 0, project: 0, minutesAgo: 26 * 60),
        task("5", "Steering support in the Codex adapter", agent: 1, project: 2, minutesAgo: 4 * 24 * 60),
        task("6", "Diff view word wrapping", agent: 0, project: 0, minutesAgo: 9 * 24 * 60),
    ]

    static let waitingTasks: [HomeWaitingTask<String>] = [
        HomeWaitingTask(
            id: "2", title: "Fix flaky permission request test", request: "Run `swift test --filter Permission`?",
            status: .needsPermission, agentName: "Codex"
        ),
        HomeWaitingTask(
            id: "3", title: "Landing page hero", request: "Should the nightly sky also show on the welcome page?",
            status: .needsInput, agentName: "Cursor"
        ),
    ]

    private static func task(
        _ id: String, _ title: String, agent: Int, project: Int, minutesAgo: Double
    ) -> HomeTask<String> {
        HomeTask(
            id: id,
            title: title,
            agentName: agents[agent].name,
            agentSymbolName: agents[agent].symbolName,
            projectName: projects[project].name,
            date: .now.addingTimeInterval(-minutesAgo * 60)
        )
    }

    static func home(
        agents: [HomeAgent<String>] = agents,
        tasks: [HomeTask<String>] = tasks,
        waiting: [HomeWaitingTask<String>] = []
    ) -> some View {
        HomeView(
            agents: agents,
            projects: projects,
            project: .constant("native"),
            recentTasks: tasks,
            waitingTasks: waiting,
            onNewTask: { _, _ in },
            onAddProject: {},
            onSelectTask: { _ in }
        )
    }

    static func welcome() -> some View {
        HomeWelcomeView(agents: agents, addProjectShortcut: KeyboardShortcut("o"), onAddProject: {})
    }
}

#Preview("Home - Light") {
    HomePreviewFixtures.home()
        .frame(width: 900, height: 780)
        .preferredColorScheme(.light)
}

#Preview("Home - Dark") {
    HomePreviewFixtures.home()
        .frame(width: 900, height: 780)
        .preferredColorScheme(.dark)
}

#Preview("Home, Needs You") {
    HomePreviewFixtures.home(waiting: HomePreviewFixtures.waitingTasks)
        .frame(width: 900, height: 900)
}

#Preview("Home, Narrow") {
    HomePreviewFixtures.home(waiting: HomePreviewFixtures.waitingTasks)
        .frame(width: 380, height: 900)
}

#Preview("Home, No Tasks") {
    HomePreviewFixtures.home(tasks: [])
        .frame(width: 900, height: 780)
}

#Preview("Home, Agents Unavailable") {
    HomePreviewFixtures.home(agents: HomePreviewFixtures.troubledAgents)
        .frame(width: 900, height: 780)
}

#Preview("Welcome - Light") {
    HomePreviewFixtures.welcome()
        .frame(width: 900, height: 780)
        .preferredColorScheme(.light)
}

#Preview("Welcome - Dark") {
    HomePreviewFixtures.welcome()
        .frame(width: 900, height: 780)
        .preferredColorScheme(.dark)
}
