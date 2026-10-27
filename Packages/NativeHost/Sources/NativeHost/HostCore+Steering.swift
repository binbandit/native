import ACP
import Foundation
import NativeHostProtocol

extension HostCore {
    func submitSteer(_ item: OutgoingPrompt, into session: HostSession) async throws -> PromptDelivery {
        let policy = agents[session.record.agentID]?.spec.steeringPolicy ?? .afterTools
        if session.steeringInFlight == nil, !session.queue.contains(where: { $0.prompt.steersAfterTools }),
            session.steeringGate.delivery(supportsSteering: session.supportsSteering, policy: policy) == .steer
        {
            return try await steer(item, into: session)
        }
        var held = item
        held.steersAfterTools = true
        try enqueue(held, in: session)
        deliverPendingSteer(in: session)
        return .queued
    }

    /// Recheck immediately before delivery: another tool may have started while a task was queued.
    func deliverPendingSteer(in session: HostSession) {
        guard session.phase == .prompting, !session.isStopping, !session.needsLoad,
            session.steeringInFlight == nil, session.steeringInterruptTurn == nil,
            let item = session.queue.first(where: { $0.prompt.steersAfterTools && !$0.isSteering }),
            let link = agents[session.record.agentID], let peer = link.peer,
            let agentSessionID = session.record.agentSessionID
        else { return }
        switch session.steeringGate.delivery(
            supportsSteering: session.supportsSteering, policy: link.spec.steeringPolicy ?? .afterTools)
        {
        case .waitForTool:
            return
        case .steer:
            Task {
                guard session.phase == .prompting, !session.isStopping, session.steeringInFlight == nil,
                    let current = session.queue.first(where: { $0.prompt.id == item.prompt.id }),
                    session.steeringGate.delivery(
                        supportsSteering: session.supportsSteering, policy: link.spec.steeringPolicy ?? .afterTools)
                        == .steer
                else { return }
                _ = try? await steer(current.prompt, into: session)
            }
        case .interruptBetweenSteps:
            // A steering interrupt has no Stop grace period or process cleanup: tools have finished.
            // Keep ownership of the message until the prompt response acknowledges the boundary.
            do {
                session.steeringInterruptTurn = session.turn?.requestID
                try peer.notify("session/cancel", CancelNotification(sessionId: agentSessionID))
            } catch {
                session.steeringInterruptTurn = nil
            }
        }
    }

    /// Adds a message to the running turn. It's recorded as steering first, so if the host stops
    /// before the agent answers, recovery can tell whether it arrived.
    func steer(_ item: OutgoingPrompt, into session: HostSession) async throws -> PromptDelivery {
        guard session.steeringInFlight == nil else { return .queued }
        session.steeringInFlight = item.id
        defer {
            session.steeringInFlight = nil
            deliverPendingSteer(in: session)
            drainQueue(session)
        }
        if let index = session.queue.firstIndex(where: { $0.prompt.id == item.id }) {
            session.queue[index].isSteering = true
            try store.setQueue(session.queue, for: session.id)
        } else {
            try enqueue(item, in: session, atFront: true, steering: true)
        }
        var delivery = PromptDelivery.queued
        if let link = agents[session.record.agentID], let peer = link.peer,
            let agentSessionID = session.record.agentSessionID
        {
            do {
                let response = try await peer.request(
                    "_session/steering",
                    SteerRequest(sessionId: agentSessionID, prompt: item.content ?? [.text(item.text)]),
                    as: RawSteerResponse.self)
                switch response.outcome {
                case "injected", "startedNewTurn":
                    // An older agent takes it as a new turn of its own; either way it's delivered.
                    session.queue.removeAll { $0.prompt.id == item.id }
                    append(
                        .prompt(
                            PromptEcho(
                                text: item.text, steered: response.outcome == "injected", origin: item.origin,
                                requestID: item.id, shown: item.isEchoed, attachments: item.attachments)),
                        to: session)
                    delivery = .steered
                default:
                    // The turn ended first; it goes out next, ahead of what was already waiting.
                    break
                }
            } catch {
                append(
                    .notice(
                        text:
                            "Couldn't add your message to the running turn, so it's queued: \(error.localizedDescription)",
                        isError: true), to: session)
            }
        }
        if let index = session.queue.firstIndex(where: { $0.prompt.id == item.id }) {
            session.queue[index].isSteering = false
            session.queue[index].prompt.steersAfterTools = false
        }
        try store.transaction {
            try store.setQueue(session.queue, for: session.id)
            try store.recordDelivery(delivery, for: item.id, in: session.id)
        }
        publish(session)
        // The defer resumes delivery after releasing the steering acknowledgement's ownership.
        return delivery
    }

}
