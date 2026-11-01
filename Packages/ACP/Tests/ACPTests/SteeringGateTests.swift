import Foundation
import Testing

@testable import ACP

struct SteeringGateTests {
    @Test func holdsThroughPartialUpdatesUntilCapturedToolCompletes() throws {
        var gate = SteeringGate()
        gate.apply(try Wire.update(Wire.readToolCall))
        #expect(gate.delivery(supportsSteering: true) == .waitForTool("Read File"))
        gate.apply(try Wire.update(Wire.readInputUpdate))
        gate.apply(try Wire.update(Wire.readMetaOnlyUpdate))
        if case .waitForTool = gate.delivery(supportsSteering: true) {} else { Issue.record("Delivered too early") }
        gate.apply(try Wire.update(Wire.readCompletedUpdate))
        #expect(gate.delivery(supportsSteering: true) == .steer)
    }

    @Test func waitsForEveryParallelToolAndUsesLatestTitle() throws {
        var gate = SteeringGate()
        gate.apply(try Wire.update(Wire.readToolCall))
        gate.apply(try Wire.update(Wire.writeToolCall))
        gate.apply(try Wire.update(Wire.writeDiffUpdate))
        gate.apply(try Wire.update(Wire.readCompletedUpdate))
        #expect(gate.delivery(supportsSteering: false) == .waitForTool("Preparing file…"))
        gate.apply(.toolCallUpdate(ToolCallUpdate(toolCallId: Wire.writeToolCallID, status: .completed)))
        #expect(gate.delivery(supportsSteering: false) == .interruptBetweenSteps)
    }

    @Test func failureReleasesTheBoundaryAndLateMetadataDoesNotReopenIt() throws {
        var gate = SteeringGate()
        for line in ToolCallNonExecutionTests.live { gate.apply(try Wire.update(line)) }
        #expect(gate.delivery(supportsSteering: true) == .steer)
        gate.apply(.toolCallUpdate(ToolCallUpdate(toolCallId: ToolCallNonExecutionTests.callID, title: "Bash")))
        #expect(gate.delivery(supportsSteering: true) == .steer)
    }

    @Test func onlyAnExplicitNonInterruptingAdapterBypassesTheHold() throws {
        var gate = SteeringGate()
        gate.apply(try Wire.update(Wire.bashToolCall))
        #expect(gate.delivery(supportsSteering: true, policy: .nonInterrupting) == .steer)
        #expect(gate.delivery(supportsSteering: false, policy: .nonInterrupting) == .waitForTool("Terminal"))
        gate.reset()
        #expect(gate.delivery(supportsSteering: false) == .interruptBetweenSteps)
    }
    @Test func unknownPluginPolicyStillHoldsTools() throws {
        let policy = try JSONDecoder().decode(SteeringPolicy.self, from: Data(#""futureMode""#.utf8))
        var gate = SteeringGate()
        gate.apply(try Wire.update(Wire.bashToolCall))
        #expect(gate.delivery(supportsSteering: true, policy: policy) == .waitForTool("Terminal"))
    }

}
