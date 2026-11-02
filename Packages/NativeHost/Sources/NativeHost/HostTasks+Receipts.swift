// Receipt ownership and stop/completion race handling adapted under the MIT License.
// Copyright (c) 2026 T3 Tools Inc.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation
import NativeHostProtocol
import NativeOrchestration

extension HostTasks {
    var supportsDurableTasks: Bool { true }

    func persistReceipt(_ key: String, _ receipt: HostDelegationReceipt) throws {
        var updated = receipts
        updated[key] = receipt
        try core.store.setMeta(
            "task_creation_receipts_v1", String(decoding: try JSONEncoder().encode(updated), as: UTF8.self))
        receipts = updated
    }

    /// Explicit cleanup may release files, but keeps every receipt endpoint for retry identity.
    /// Include the whole connected family so a settled original result cannot hide follow-up work.
    func receiptWorkHasSettled(involving id: HostSessionID) -> Bool {
        guard receiptsReadable else { return false }
        var family: Set<HostSessionID> = [id]
        var previousCount = 0
        while previousCount != family.count {
            previousCount = family.count
            for receipt in receipts.values where family.contains(receipt.parentID) || family.contains(receipt.childID) {
                family.insert(receipt.parentID)
                family.insert(receipt.childID)
            }
        }
        for (key, receipt) in receipts where family.contains(receipt.parentID) {
            guard creationFlights[key] == nil else { return false }
            guard receipt.failure != nil || (receipt.result != nil && receipt.delivery != .pending) else {
                return false
            }
        }
        return family.compactMap { core.sessions[$0] }.allSatisfy {
            !$0.holdsRestart && !$0.isStopping && $0.queue.isEmpty
                && $0.pendingPermissions.isEmpty && $0.pendingQuestions.isEmpty
        }
    }

    func startTaskReceipt(_ request: TaskRequest) async throws -> TaskStartReceipt {
        guard receiptsReadable else {
            throw TaskLaunchValidation.Refusal("Native cannot read child task receipts. No new child was started.")
        }
        guard let parent = session(holding: request.parent) else { throw HostTaskError.parentClosed }
        let key = "\(parent.id.rawValue)/\(request.creationKey ?? "unkeyed-\(request.id)")"
        let intent = HostDelegationReceipt.Intent(request)
        if let existing = receipts[key] {
            guard existing.intent == intent else {
                throw TaskLaunchValidation.Refusal("This creation_key already belongs to a different request.")
            }
            if let flight = creationFlights[key] { return try await flight.value }
            if existing.accepted, let task = existing.task {
                return TaskStartReceipt(task: task, snapshot: .init(status: .running))
            }
            if let failure = existing.failure { throw TaskLaunchValidation.Refusal(failure) }
            // A durable admission can be completed using the host's existing prompt receipt. A
            // session/new cut off before admission is ambiguous at the provider, so never repeat it.
            guard existing.task != nil else {
                throw TaskLaunchValidation.Refusal(
                    "Creation was interrupted before admission. Native will not create a second child. Check tasks before using a new key."
                )
            }
        } else {
            try checkParent(parent, request: request)
            try persistReceipt(key, HostDelegationReceipt(intent: intent, parentID: parent.id))
        }
        let flight = Task { try await self.finishCreation(key, request: request, parent: parent) }
        creationFlights[key] = flight
        defer { creationFlights[key] = nil }
        return try await flight.value
    }

    private func finishCreation(
        _ key: String, request: TaskRequest, parent: HostSession
    ) async throws -> TaskStartReceipt {
        do {
            guard let receipt = receipts[key], receipt.delivery != .suppressed else {
                throw TaskLaunchValidation.Refusal("The parent stopped before the child was admitted.")
            }
            let task: OrchestrationTask
            if let admitted = receipt.task {
                task = admitted
                guard let child = core.sessions[receipt.childID] else { throw HostTaskError.closed }
                if try core.store.delivery(for: receipt.promptID) == nil {
                    guard child.record.lastStopReason == nil else {
                        throw TaskLaunchValidation.Refusal(
                            "The original prompt receipt is unavailable. Native will not repeat the child prompt.")
                    }
                    try await core.load(child)
                    try await prepare(child, request: request, parent: parent)
                    try sendFirstPrompt(request, to: child, parent: parent, key: key)
                }
            } else {
                task = try await createTask(request, key: key, receipt: receipt)
            }
            // Stop may have claimed delivery while admission was suspended.
            captureAvailableResults()
            scheduleCompletions()
            return TaskStartReceipt(task: task, snapshot: .init(status: .running))
        } catch {
            if var receipt = receipts[key] {
                receipt.failure = error.localizedDescription
                receipt.delivery = .suppressed
                try persistReceipt(key, receipt)
            }
            throw error
        }
    }

    func sendFirstPrompt(
        _ request: TaskRequest, to child: HostSession, parent: HostSession, key: String
    ) throws {
        try checkParent(parent, request: request)
        try verifyPrepared(child, request: request, parent: parent)
        guard var receipt = receipts[key], receipt.delivery != .suppressed else {
            throw TaskLaunchValidation.Refusal("The parent stopped before the child was admitted.")
        }
        receipt.accepted = true
        try commitDelegatedPrompt(
            request.prompt, to: child, id: receipt.promptID, key: key, receipt: receipt)
    }

    /// The receipt and the ordinary host turn commit together. This closes the crash window even
    /// after the general prompt receipt retention period has expired, without a history schema change.
    func commitDelegatedPrompt(
        _ text: String, to session: HostSession, id: UUID, key: String, receipt: HostDelegationReceipt
    ) throws {
        guard receiptsReadable, session.phase == .idle, session.turn == nil, session.queue.isEmpty,
            !session.needsLoad, session.hiddenCommand == nil, session.stopRequestedAt == nil
        else { throw TaskLaunchValidation.Refusal("The task is not ready to accept the delegated prompt.") }
        try core.require(.agentTools)
        try core.requirePermission(in: session)
        var updated = receipts
        updated[key] = receipt
        let encoded = String(decoding: try JSONEncoder().encode(updated), as: UTF8.self)
        let previous = receipts
        do {
            try core.startTurn(
                in: session, prompt: OutgoingPrompt(id: id, text: text, isEchoed: false, origin: .task),
                committing: { [self] in
                    try core.store.setMeta("task_creation_receipts_v1", encoded)
                    // startTurn publishes after commit. Its synchronous observers must see ownership
                    // before they can capture another result or update the receipt dictionary.
                    receipts = updated
                })
        } catch {
            receipts = previous
            throw error
        }
    }
}
