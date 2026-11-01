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
    /// Capture before the host drains an already queued follow-up. An asynchronous observer could
    /// otherwise read the second turn's reply and lose the original result.
    func captureAvailableResults() {
        guard receiptsReadable else { return }
        do {
            var changed = true
            while changed {
                changed = false
                for key in Array(receipts.keys).sorted() {
                    if try captureResult(key) { changed = true }
                }
            }
        } catch {
            receiptsReadable = false
            core.logger.error("Could not save an original child result. Automatic completion delivery is disabled.")
        }
    }

    /// A child's original result includes its descendants. Pending wakes belong to the child until
    /// its parent has read them or the host has committed the follow-up turn.
    func hasUnfinishedDescendants(_ parent: HostSessionID) -> Bool {
        receipts.values.contains {
            $0.parentID == parent && $0.task != nil && $0.failure == nil && $0.delivery != .suppressed
                && ($0.result == nil || ($0.intent.notify && $0.delivery == .pending))
        }
    }

    func scheduleCompletions() {
        guard receiptsReadable, completionWorker == nil else { return }
        completionWorker = Task { [weak self] in
            guard let self else { return }
            await reconcileCompletions()
            completionWorker = nil
        }
    }

    /// Uses the ordinary load/recovery and prompt delivery receipts. Nothing depends on a client
    /// staying attached, and a crash between prompt commit and receipt update cannot send twice.
    private func reconcileCompletions() async {
        var progressed = true
        while progressed && receiptsReadable {
            progressed = false
            for key in Array(receipts.keys).sorted() {
                guard let receipt = receipts[key], receipt.accepted, receipt.failure == nil,
                    let child = core.sessions[receipt.childID]
                else { continue }
                do {
                    if receipt.result == nil, child.turn == nil, child.retryAt == nil {
                        if child.needsLoad {
                            try await core.load(child)
                        }
                        if try captureResult(key) { progressed = true }
                    }
                    guard let current = receipts[key], current.result != nil, current.intent.notify,
                        current.delivery == .pending, let parent = core.sessions[current.parentID],
                        canWake(parent)
                    else { continue }
                    if parent.needsLoad { try await core.load(parent) }
                    guard canWake(parent), let latest = receipts[key], latest.delivery == .pending else { continue }
                    let result = latest.result
                    let text = """
                        Child task \(latest.task?.id ?? "") finished with status \(result?.status.rawValue ?? "failed").
                        \(result?.detail ?? "")
                        \(result?.reply ?? "The task returned no reply.")
                        This is its original result. Use get_task for its current state or send_message to follow up.
                        """
                    guard var delivered = receipts[key], delivered.delivery == .pending, canWake(parent) else {
                        continue
                    }
                    delivered.delivery = .delivered
                    try commitDelegatedPrompt(text, to: parent, id: delivered.wakeID, key: key, receipt: delivered)
                    progressed = true
                } catch {
                    // Offline agents, policy changes and paused parents keep their pending receipt.
                    // The next session update or heartbeat retries the same durable request id.
                }
            }
            wakeSettledWaiters()
        }
    }

    private func canWake(_ session: HostSession) -> Bool {
        core.sessions[session.id] === session && session.turn == nil && session.retryAt == nil
            && session.stopRequestedAt == nil && !session.record.isQueuePaused
            && session.hiddenCommand == nil && session.queue.isEmpty && (session.phase == .idle || session.needsLoad)
    }

    @discardableResult
    func captureResult(_ key: String) throws -> Bool {
        guard var receipt = receipts[key], receipt.accepted, receipt.result == nil,
            let child = core.sessions[receipt.childID], !child.needsLoad,
            child.turn == nil, child.retryAt == nil, !hasUnfinishedDescendants(child.id)
        else { return false }
        var result = ownSnapshot(child)
        guard result.status != .running, result.status != .needsApproval else { return false }
        // Receipts and automatic follow-ups have a fixed content budget; the full transcript stays
        // in the session's existing history store.
        if let reply = result.reply, reply.count > 32_768 {
            result.reply =
                String(reply.prefix(32_768)) + "\n[Original result truncated; open the child transcript for the rest.]"
        }
        result.detail = result.detail.map { String($0.prefix(2048)) }
        receipt.result = result
        if !receipt.intent.notify, receipt.delivery == .pending { receipt.delivery = .consumed }
        try persistReceipt(key, receipt)
        return true
    }

    func originalResult(of ref: TaskSessionRef) -> TaskSnapshot? {
        guard let child = session(holding: ref) else { return nil }
        return receipts.values.first { $0.childID == child.id }?.result
    }

    func acknowledgeResult(of ref: TaskSessionRef, by clientID: UUID) throws {
        guard let child = session(holding: ref),
            let key = receipts.first(where: { $0.value.childID == child.id })?.key,
            receipts[key]?.parentID == HostSessionID(clientID)
        else { return }
        try captureResult(key)
        if var receipt = receipts[key], receipt.result != nil, receipt.delivery == .pending {
            receipt.delivery = .consumed
            try persistReceipt(key, receipt)
        }
        scheduleCompletions()
    }

    private func wakeSettledWaiters() {
        for receipt in receipts.values {
            if let task = receipt.task, let child = core.sessions[receipt.childID] {
                showCard(of: task, session: child)
            }
        }
        for id in Array(waiters.keys) {
            guard let session = core.sessions[id], snapshot(session, reading: false).status != .running else {
                continue
            }
            for waiter in (waiters.removeValue(forKey: id) ?? [:]).values {
                waiter.timer.cancel()
                waiter.continuation.resume()
            }
        }
    }
}
