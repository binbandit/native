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

extension HostTasks {
    /// Claim the entire owned subtree before the first suspension. A late completion cannot lift
    /// Stop's queue pause or wake a parent, even when the parent had already finished its turn.
    func stopDelegations(of root: HostSession) -> [HostSession] {
        var ids: Set<HostSessionID> = [root.id]
        var changed = true
        while changed {
            changed = false
            for receipt in receipts.values where ids.contains(receipt.parentID) {
                if ids.insert(receipt.childID).inserted { changed = true }
            }
            // Include tasks created before durable receipts were introduced.
            for task in records {
                guard let parent = session(holding: task.parent), ids.contains(parent.id),
                    let child = session(holding: task.session)
                else { continue }
                if ids.insert(child.id).inserted { changed = true }
            }
        }
        for id in ids { stopEpochs[id, default: 0] += 1 }
        let keys = receipts.keys.filter { key in
            receipts[key].map { ids.contains($0.parentID) || ids.contains($0.childID) } ?? false
        }
        let wakeIDs = Set(keys.compactMap { receipts[$0]?.wakeID })
        for key in keys {
            guard var receipt = receipts[key] else { continue }
            receipt.delivery = .suppressed
            let stopped = [receipt.parentID, receipt.childID].compactMap { core.sessions[$0]?.turn?.requestID }
            receipt.stoppedTurnIDs = Array(Set(receipt.stoppedTurnIDs + stopped))
            receipts[key] = receipt
        }
        let sessions = ids.compactMap { core.sessions[$0] }
        // The pause is durable for a stopped delegation tree, including an idle root. A later user
        // message can resume work, but suppressed completion receipts stay suppressed.
        if !keys.isEmpty || ids.count > 1 {
            for session in sessions {
                session.record.isQueuePaused = true
                session.queue.removeAll { wakeIDs.contains($0.prompt.id) }
            }
        }
        do {
            try core.store.transaction {
                for key in keys {
                    if let receipt = receipts[key] { try persistReceipt(key, receipt) }
                }
                for session in sessions {
                    try core.store.setQueue(session.queue, for: session.id)
                    try core.store.updateSession(session.record)
                }
            }
        } catch {
            receiptsReadable = false
            core.logger.error("Could not persist child task Stop. Automatic completion delivery is disabled.")
        }
        return sessions.filter { $0.id != root.id }
    }

    /// A host crash during cancellation must finish that same turn as cancelled, while a later
    /// explicit user prompt (with a new request id) can still recover normally.
    func wasStoppedDelegation(_ turn: UnfinishedTurn) -> Bool {
        receipts.values.contains { $0.stoppedTurnIDs.contains(turn.requestID) }
    }
}
