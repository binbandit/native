import Foundation
import Testing

@testable import ACP

struct QueuedSteeringCapabilityTests {
    @Test(arguments: [nil, SteeringPolicy.afterTools, .nonInterrupting, .unknown])
    func advertisedSteeringAllowsQueuedInput(policy: SteeringPolicy?) throws {
        let response = try Wire.decode(InitializeResponse.self, from: Wire.initializeResult)
        #expect(
            SteeringGate.supportsQueuedSteering(supportsSteering: response.agentCapabilities.steering, policy: policy))
    }

    @Test func explicitToolBoundaryDeliveryAllowsQueuedInputWithoutAnExtension() {
        #expect(SteeringGate.supportsQueuedSteering(supportsSteering: false, policy: .afterTools))
    }

    @Test(arguments: [nil, SteeringPolicy.nonInterrupting, .unknown])
    func missingSteeringAndNoToolBoundaryDeclarationHideTheAction(policy: SteeringPolicy?) {
        #expect(!SteeringGate.supportsQueuedSteering(supportsSteering: false, policy: policy))
    }

}
