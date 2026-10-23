#if DEBUG
import NativeSetup
import SwiftUI

enum HomeAgentFailurePreviewFixtures {
    static let agent = HomeAgent(
        id: "exit-agent", name: "Exit Agent", symbolName: "terminal",
        availability: .unavailable(AgentRuntimeStatus.failed("The process exited while starting.").label),
        remedy: HomeAgentRemedy("Restart Exit Agent") {})

    static let failure = AgentStartupFailure(agents: [("Exit Agent", .stopped), ("Second Agent", .stopped)])

    static let agents = [
        agent,
        HomeAgent(
            id: "second-agent", name: "Second Agent", symbolName: "terminal",
            availability: .unavailable("Stopped"), remedy: HomeAgentRemedy("Restart Second Agent") {}),
    ]
}

#Preview("Home - Agent failed to start") {
    DSPreviewPair {
        HomeAgentCard(agent: HomeAgentFailurePreviewFixtures.agent, isBusy: false, onNewTask: {})
            .frame(width: 240, height: HomeLayout.cardHeight)
    }
}

#Preview("Home - All agents failed to start") {
    DSPreviewPair {
        HomeView<String, String, String>(
            agents: HomeAgentFailurePreviewFixtures.agents,
            projects: HomePreviewFixtures.projects, project: .constant("native"), recentTasks: [],
            startupFailure: HomeAgentFailurePreviewFixtures.failure,
            onNewTask: { _, _ in }, onAddProject: {}, onSelectTask: { _ in }
        )
        .frame(width: 700, height: 780)
    }
}
#endif
