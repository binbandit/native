import Testing

@testable import TaskDefaults

struct TaskDefaultsTests {
    @Test func precedenceAndReset() {
        let values = ["agent", "last", "user", "project"]
        let full = TaskDefaultResolution(
            offered: values, agent: "agent", user: "user", project: "project", lastUsed: "last")
        #expect(full.value == "project" && full.source == .project)
        let reset = TaskDefaultResolution(offered: values, agent: "agent", user: "user", project: "", lastUsed: "last")
        #expect(reset.value == "user" && reset.source == .user)
        #expect(TaskDefaultResolution(offered: values, agent: "agent", lastUsed: "last").source == .lastUsed)
        #expect(TaskDefaultResolution(offered: values, agent: "agent").source == .agent)
    }

    @Test func unavailableChoiceKeepsAgent() {
        let value = TaskDefaultResolution(offered: ["agent", "user"], agent: "agent", user: "user", project: "gone")
        #expect(value.value == "agent" && value.unavailable && value.requested == "gone")
    }

    @Test func policyUsesTheSameFirstAllowedFallbackAsStartup() {
        let value = TaskDefaultResolution(
            offered: ["ask", "edit", "auto"], agent: "auto", user: "auto", forbidden: ["auto"])
        #expect(value.value == "ask" && value.source == .organization && value.restricted)
        let allowed = TaskDefaultResolution(
            offered: ["ask", "edit", "auto"], agent: "ask", user: "edit", forbidden: ["auto"])
        #expect(allowed.value == "edit" && allowed.source == .user && !allowed.restricted)
    }

    @Test func allForbiddenHasNoAllowedValue() {
        let value = TaskDefaultResolution(offered: ["auto"], agent: "auto", forbidden: ["auto"])
        #expect(value.value == nil && value.restricted)
    }

    @Test func missingChoicesStayUnknown() {
        let value = TaskDefaultResolution(offered: [], agent: nil, user: "model")
        #expect(value.value == nil && value.unavailable)
    }

    @Test func contextExcludesDisabledAndRetainsUnknowns() {
        let budget = TaskContextBudget(
            parts: [
                .init(.tools, tokens: 9000), .init(.tools, tokens: 4000, included: false),
                .init(.instructions, tokens: 1000), .init(.skills, tokens: nil),
                .init(.tools, tokens: nil, included: false),
            ], window: 200000)
        #expect(budget.knownTokens == 10000 && budget.unknownCount == 1)
        #expect(budget.fraction(for: .tools) == 0.045)
        #expect(TaskContextBudget(parts: [], window: 0).window == nil)
        #expect(TaskContextBudget.estimate(bytes: 5) == 2)
        #expect(TaskContextBudget.estimate(bytes: -1) == 0)
    }
}
