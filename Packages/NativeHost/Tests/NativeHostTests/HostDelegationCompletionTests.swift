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

import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import Testing

@Suite(.serialized, .timeLimit(.minutes(2)))
struct HostDelegationCompletionTests {
    private func start(
        _ recorder: Recorder, parent: HostSessionID, prompt: String, key: String
    ) async throws -> HostTask {
        let result = try await recorder.client.callTool(
            CallToolParams(
                sessionID: parent, tool: "start_task",
                arguments: .object([
                    "agent": .string("fake"), "prompt": .string(prompt), "creation_key": .string(key),
                ])))
        #expect(!result.isError, "\(result.text)")
        let id = try #require(result.structuredContent?["task_id"]?.stringValue)
        return try #require(try await recorder.client.tasks().first { $0.id == id })
    }

    @Test func pendingResultReachesDisconnectedParentAfterHostRestartExactlyOnce() async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        try harness.start()
        let first = try await harness.connect()
        let parent = try await first.client.newSession(
            NewSessionParams(agentID: "fake", cwd: harness.root.path, attach: true))
        _ = try await first.client.prompt(PromptParams(sessionID: parent.id, text: "slow 30"))
        let task = try await start(first, parent: parent.id, prompt: "slow 3", key: "restart")
        let child = try #require(task.sessionID)
        try await first.client.attach(child)
        try await first.wait("child terminal before parent") { await $0.turnsEnded(child).last == "end_turn" }
        await first.stop()
        harness.kill()
        try harness.start()
        let second = try await harness.connect()
        try await second.client.attach(parent.id)
        try await second.wait("host completion wake") { _ in
            harness.received.contains { $0.hasPrefix("prompt\tChild task \(task.id) finished") }
        }
        try await second.wait("completion turn") { await $0.turnsEnded(parent.id).count >= 2 }
        #expect(harness.received.filter { $0.hasPrefix("prompt\tChild task \(task.id) finished") }.count == 1)
        await second.stop()
        harness.kill()
        try harness.start()
        let third = try await harness.connect()
        let result = try await third.client.callTool(
            CallToolParams(sessionID: parent.id, tool: "get_task", arguments: .object(["task_id": .string(task.id)])))
        #expect(result.structuredContent?["original_result"]?["reply"]?.stringValue?.contains("tick 3") == true)
        #expect(harness.received.filter { $0.hasPrefix("prompt\tChild task \(task.id) finished") }.count == 1)
        await third.stop()
    }

    @Test func idleChildWaitsForDescendantsBeforeReportingItsOriginalResult() async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        try harness.start()
        let recorder = try await harness.connect()
        let parent = try await recorder.client.newSession(NewSessionParams(agentID: "fake", cwd: harness.root.path))
        let childTask = try await start(recorder, parent: parent.id, prompt: "slow 4", key: "child")
        let child = try #require(childTask.sessionID)
        try await recorder.client.attach(child)
        _ = try await start(recorder, parent: child, prompt: "slow 12", key: "grandchild")
        try await recorder.wait("child's own turn") { await $0.turnsEnded(child).last == "end_turn" }
        let waiting = try await recorder.client.callTool(
            CallToolParams(
                sessionID: parent.id, tool: "get_task", arguments: .object(["task_id": .string(childTask.id)])))
        #expect(waiting.structuredContent?["status"]?.stringValue == "running")
        #expect(waiting.structuredContent?["detail"]?.stringValue?.contains("child tasks") == true)
        #expect(waiting.structuredContent?["original_result"] == nil)
        let result = try await recorder.client.callTool(
            CallToolParams(
                sessionID: parent.id, tool: "wait_for_task", arguments: .object(["task_id": .string(childTask.id)])))
        #expect(result.structuredContent?["status"]?.stringValue == "idle")
        #expect(result.structuredContent?["original_result"]?["reply"]?.stringValue?.contains("tick 12") == true)
        await recorder.stop()
    }

    @Test func hostCrashDuringStopDoesNotResumeTheStoppedSubtree() async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        try harness.start()
        let first = try await harness.connect()
        let parent = try await first.client.newSession(NewSessionParams(agentID: "fake", cwd: harness.root.path))
        let task = try await start(first, parent: parent.id, prompt: "stubborn 30", key: "stopping")
        let child = try #require(task.sessionID)
        try await first.client.attach(child)
        try await first.wait("child started") { await $0.agentText(child).contains("tick 1") }
        try await first.client.cancel(parent.id)
        harness.kill()
        await first.stop()
        try harness.start()
        let second = try await harness.connect()
        try await second.client.attach(child)
        try await second.wait("durable cancellation") { await $0.listed(child)?.lastStopReason == "cancelled" }
        #expect(await second.recoveries(child).isEmpty)
        #expect(!harness.received.contains { $0.hasPrefix("prompt\tChild task ") })
        // A new explicit user turn is not the stopped turn and can recover normally.
        _ = try await second.client.prompt(PromptParams(sessionID: child, text: "slow 30"))
        try await second.wait("new turn started") { await $0.agentText(child).contains("tick 2") }
        harness.kill()
        await second.stop()
        try harness.start()
        let third = try await harness.connect()
        try await third.client.attach(child)
        try await third.wait("new user turn recovers") { await !$0.recoveries(child).isEmpty }
        await third.stop()
    }

    @Test func stopOnIdleParentCancelsSubtreeAndSuppressesWakesAcrossRestart() async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        try harness.start()
        let recorder = try await harness.connect()
        let parent = try await recorder.client.newSession(NewSessionParams(agentID: "fake", cwd: harness.root.path))
        let childTask = try await start(recorder, parent: parent.id, prompt: "slow 30", key: "child")
        let child = try #require(childTask.sessionID)
        let grandchildTask = try await start(recorder, parent: child, prompt: "slow 30", key: "grandchild")
        let grandchild = try #require(grandchildTask.sessionID)
        try await recorder.client.attach(child)
        try await recorder.client.attach(grandchild)
        try await recorder.wait("grandchild started") { await $0.agentText(grandchild).contains("tick 1") }
        try await recorder.client.cancel(parent.id)
        try await recorder.wait("subtree cancelled") {
            let childStopped = await $0.turnsEnded(child).last == "cancelled"
            let grandchildStopped = await $0.turnsEnded(grandchild).last == "cancelled"
            return childStopped && grandchildStopped
        }
        await recorder.stop()
        harness.kill()
        try harness.start()
        let second = try await harness.connect()
        for task in [childTask, grandchildTask] {
            let parentID = try #require(task.parentSessionID)
            let result = try await second.client.callTool(
                CallToolParams(sessionID: parentID, tool: "get_task", arguments: .object(["task_id": .string(task.id)]))
            )
            #expect(result.structuredContent?["status"]?.stringValue == "cancelled")
        }
        #expect(!harness.received.contains { $0.hasPrefix("prompt\tChild task ") })
        await second.stop()
    }
}
