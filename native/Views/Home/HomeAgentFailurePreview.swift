#if DEBUG
import SwiftUI

enum HomeAgentFailurePreviewFixtures {
    static let agent = HomeAgent(
        id: "exit-agent", name: "Exit Agent", symbolName: "terminal",
        availability: .unavailable(AgentRuntimeStatus.failed("The process exited while starting.").label),
        remedy: HomeAgentRemedy("Restart Exit Agent") {})
}

#Preview("Home - Agent failed to start") {
    DSPreviewPair {
        HomeAgentCard(agent: HomeAgentFailurePreviewFixtures.agent, isBusy: false, onNewTask: {})
            .frame(width: 240, height: HomeLayout.cardHeight)
    }
}
#endif
