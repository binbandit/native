import ACP
import Foundation
import NativeHostProtocol

extension SessionModel {
    var supportsQueuedSteering: Bool {
        SteeringGate.supportsQueuedSteering(
            supportsSteering: hostSummary?.supportsSteering ?? supportsSteering, policy: agent.manifest.steeringPolicy)
    }

    var steeringDelivery: SteeringGate.Delivery {
        steeringGate.delivery(supportsSteering: supportsSteering, policy: agent.manifest.steeringPolicy ?? .afterTools)
    }

    @discardableResult
    func submitSteer(_ text: String, attachments: [PromptAttachment], echo: Bool) async -> FollowUpDelivery {
        if steeringDelivery == .steer, !isDeliveringSteer, !queue.items.contains(where: \.steersAfterTools) {
            return await steer(text, attachments: attachments, echo: echo)
        }
        let item = QueuedPrompt(text, attachments: attachments, isEchoed: echo, steersAfterTools: true)
        let index = queue.items.firstIndex(where: { !$0.steersAfterTools }) ?? queue.items.endIndex
        queue.restore(item, at: index)
        deliverPendingSteer()
        return .queued
    }

    func deliverPendingSteer() {
        guard host == nil, phase == .prompting, !isStopping, !isDeliveringSteer, !isSteeringBetweenSteps,
            let item = queue.items.first(where: \.steersAfterTools)
        else { return }
        switch steeringDelivery {
        case .waitForTool: break
        case .steer:
            let generation = turnGeneration
            Task {
                guard phase == .prompting, turnGeneration == generation, !isStopping, !isDeliveringSteer,
                    steeringDelivery == .steer,
                    let current = queue.remove(item.id)
                else { return }
                await steer(current.text, attachments: current.attachments, echo: current.isEchoed)
            }
        case .interruptBetweenSteps:
            isSteeringBetweenSteps = true
            let generation = turnGeneration
            Task {
                guard phase == .prompting, turnGeneration == generation, !isStopping,
                    steeringDelivery == .interruptBetweenSteps, queue.index(of: item.id) != nil
                else {
                    if turnGeneration == generation { isSteeringBetweenSteps = false }
                    return
                }
                do {
                    try await connection?.notify(CancelNotification(sessionId: id))
                } catch {
                    isSteeringBetweenSteps = false
                }
            }
        }
    }

    /// Adds `text` to the running turn. If the turn ended first, it goes to the front of the queue.
    @discardableResult
    private func steer(_ text: String, attachments: [PromptAttachment], echo: Bool) async -> FollowUpDelivery {
        isDeliveringSteer = true
        defer {
            isDeliveringSteer = false
            deliverPendingSteer()
            drainQueue()
        }
        var delivery = FollowUpDelivery.queued
        do {
            let prompt = promptBlocks(text, attachments: attachments)
            guard let connection else { throw SendError.disconnected }
            let response = try await connection.send(SteerRequest(sessionId: id, prompt: prompt))
            switch response.outcome {
            case .injected:
                if echo {
                    state.appendUserMessage(
                        text, attachments: MessageAttachment.shown(attachments, capabilities: promptCapabilities),
                        steered: true)
                }
                delivery = .steered
            case .startedNewTurn:
                // An older agent took it as a new prompt of its own; it's been delivered.
                if echo {
                    state.appendUserMessage(
                        text, attachments: MessageAttachment.shown(attachments, capabilities: promptCapabilities))
                }
                delivery = .steered
            case .promptRequired, .other:
                queue.prepend(text, attachments: attachments, isEchoed: echo)
            }
        } catch {
            queue.append(text, attachments: attachments, isEchoed: echo)
            state.appendNotice(
                "Couldn't add your message to the running turn, so it's queued: \(error.localizedDescription)",
                isError: true)
        }
        // The defer resumes delivery after releasing the steering acknowledgement's ownership.
        return delivery
    }
}
