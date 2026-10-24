import Foundation
import Testing

@testable import ACP

@Suite struct PlanReviewTests {
    private func step() throws -> PlanEntry {
        try JSONDecoder().decode(
            PlanEntry.self,
            from: Data(#"{"content":"Keep the original layout","priority":"medium","status":"completed"}"#.utf8))
    }

    @Test func previousTurnChecklistDoesNotStandInForNewProposal() throws {
        var state = SessionState()
        state.appendUserMessage("First change")
        state.apply(.plan([try step()]))
        state.endTurn(.endTurn)
        state.appendUserMessage("A different change")
        let request = try JSONDecoder().decode(
            RequestPermissionRequest.self,
            from: Data(
                #"{"sessionId":"s","toolCall":{"toolCallId":"proposal","title":"Review a different proposal","kind":"switch_mode","rawInput":{"plan":"Replace the layout"}},"options":[{"optionId":"approve","name":"Approve","kind":"allow_once"}]}"#
                    .utf8))
        state.requestPermission(request, id: .int(7))

        #expect(state.plan.count == 1)
        #expect(state.currentTurnPlan.isEmpty)
        #expect(state.permissionRequests.first?.rawInput == .object(["plan": .string("Replace the layout")]))
    }

    @Test func freshChecklistSurvivesSteeringWithinItsTurn() throws {
        var state = SessionState()
        state.appendUserMessage("Make a plan")
        state.apply(.plan([try step()]))
        state.appendUserMessage("Keep it small", steered: true)
        #expect(state.currentTurnPlan == state.plan)
    }

    @Test func unassociatedPlanDoesNotBecomeTheFirstTurnsProposal() throws {
        var state = SessionState()
        state.apply(.plan([try step()]))
        state.appendUserMessage("A new proposal")
        #expect(state.currentTurnPlan.isEmpty)
    }
}
