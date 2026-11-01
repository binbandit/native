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

/// Separate from session history: the original command, result and delivery ownership never change
/// when a user follows up in the same session.
struct HostDelegationReceipt: Codable, Sendable {
    struct Intent: Codable, Equatable, Sendable {
        var agent: String
        var text: String
        var title: String
        var options: TaskLaunchOptions
        var notify: Bool

        init(_ request: TaskRequest) {
            agent = request.agent.id
            text = request.text
            title = request.title
            options = request.options
            notify = request.notifyOnCompletion ?? true
        }
    }

    enum Delivery: String, Codable, Sendable {
        case pending, delivered, consumed, suppressed
    }

    var intent: Intent
    var parentID: HostSessionID
    var childID = HostSessionID()
    var promptID = UUID()
    var wakeID = UUID()
    var task: OrchestrationTask?
    var accepted = false
    var failure: String?
    var result: TaskSnapshot?
    var delivery: Delivery = .pending
    var stoppedTurnIDs: [UUID] = []
}
