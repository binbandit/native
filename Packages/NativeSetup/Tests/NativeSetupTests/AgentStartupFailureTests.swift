import Testing

@testable import NativeSetup

@Suite("All agents failed to start")
struct AgentStartupFailureTests {
    @Test func namesEveryFailedAgent() throws {
        let failure = try #require(
            AgentStartupFailure(agents: [("Exit Agent", .stopped), ("Second Agent", .stopped)]))
        #expect(failure.agentNames == ["Exit Agent", "Second Agent"])
        #expect(failure.title == "No agents could start")
        #expect(failure.message.contains("Exit Agent, Second Agent failed to start"))
        #expect(failure.message.contains("Restart"))
        #expect(failure.message.contains("Settings > Agents"))
    }

    @Test(arguments: [SetupReport.Agent.State.ready, .starting])
    func retryOrRecoveryClearsFailure(_ state: SetupReport.Agent.State) {
        #expect(AgentStartupFailure(agents: [("Exit Agent", .stopped), ("Second Agent", state)]) == nil)
    }

    @Test func failedRetryRestoresRecovery() {
        let before = AgentStartupFailure(agents: [("Exit Agent", .stopped)])
        #expect(before != nil)
        #expect(AgentStartupFailure(agents: [("Exit Agent", .starting)]) == nil)
        #expect(AgentStartupFailure(agents: [("Exit Agent", .stopped)]) == before)
        #expect(AgentStartupFailure(agents: [("Exit Agent", .ready)]) == nil)
    }

    @Test(arguments: [SetupReport.Agent.State.notInstalled, .turnedOff, .notAllowed])
    func unavailableAgentsAreNotStartupFailures(_ state: SetupReport.Agent.State) {
        #expect(AgentStartupFailure(agents: [("Other Agent", state)]) == nil)
        #expect(
            AgentStartupFailure(agents: [("Exit Agent", .stopped), ("Other Agent", state)])?.agentNames
                == ["Exit Agent"])
    }

    @Test func noAgentsIsNotAFailedLaunch() {
        #expect(AgentStartupFailure(agents: []) == nil)
    }
}
