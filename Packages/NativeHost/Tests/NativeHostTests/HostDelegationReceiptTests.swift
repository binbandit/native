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

// These tools require the host's Network and CryptoKit MCP transport.
#if canImport(Network) && canImport(CryptoKit)
import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import Testing

@Suite(.serialized, .timeLimit(.minutes(2)))
struct HostDelegationReceiptTests {
    private func start(
        _ client: NativeHostClient, parent: HostSessionID, key: String, prompt: String = "hello",
        notify: Bool = false, model: String? = nil
    ) async throws -> ToolResult {
        var args: [String: JSONValue] = [
            "agent": .string("fake"), "prompt": .string(prompt), "creation_key": .string(key),
            "notify_on_completion": .bool(notify),
        ]
        args["model"] = model.map(JSONValue.string)
        return try await client.callTool(
            CallToolParams(sessionID: parent, tool: "start_task", arguments: .object(args)))
    }

    @Test func retriesShareOneChildAndTheOriginalCreationReceiptAcrossRestart() async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        try harness.start()
        let first = try await harness.connect()
        let parent = try await first.client.newSession(NewSessionParams(agentID: "fake", cwd: harness.root.path))
        async let one = start(first.client, parent: parent.id, key: "one", prompt: "slow 4")
        async let two = start(first.client, parent: parent.id, key: "one", prompt: "slow 4")
        let (a, b) = try await (one, two)
        #expect(!a.isError, "\(a.text)")
        #expect(a == b)
        let task = try #require(try await first.client.tasks().first)
        let child = try #require(task.sessionID)
        try await first.client.attach(child)
        try await first.wait("original child result") { await $0.turnsEnded(child).last == "end_turn" }
        #expect(try await first.client.tasks().count == 1)
        let changed = try await start(first.client, parent: parent.id, key: "one", prompt: "changed")
        #expect(changed.isError)
        #expect(changed.text.contains("different request"))
        harness.kill()
        await first.stop()
        try harness.start()
        let second = try await harness.connect()
        let replay = try await start(second.client, parent: parent.id, key: "one", prompt: "slow 4")
        #expect(replay == a)
        #expect(try await second.client.tasks().map(\.id) == [task.id])
        #expect(harness.received.filter { $0.hasPrefix("prompt\t") }.count == 1)
        await second.stop()
    }

    @Test func interruptedUnadmittedCreationRefusesToCreateAnotherChild() async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        let gate = harness.root.appending(path: "release-config")
        harness.agentEnvironment["FAKE_AGENT_CONFIG_GATE"] = gate.path
        try harness.start()
        let first = try await harness.connect()
        let parent = try await first.client.newSession(NewSessionParams(agentID: "fake", cwd: harness.root.path))
        let flight = Task { try await start(first.client, parent: parent.id, key: "interrupted", model: "beta") }
        try await first.wait("child before admission") { _ in harness.received.contains("config-pending\tmodel=beta") }
        let news = try String(contentsOf: harness.agentStore.appending(path: "news.log"), encoding: .utf8)
        harness.kill()
        await first.stop()
        _ = try? await flight.value
        try harness.start()
        let second = try await harness.connect()
        let replay = try await start(second.client, parent: parent.id, key: "interrupted", model: "beta")
        #expect(replay.isError)
        #expect(replay.text.contains("will not create a second child"))
        #expect(try String(contentsOf: harness.agentStore.appending(path: "news.log"), encoding: .utf8) == news)
        #expect(!harness.received.contains { $0.hasPrefix("prompt\t") })
        await second.stop()
    }

    @Test func originalResultSurvivesFollowUps() async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        try harness.start()
        let recorder = try await harness.connect()
        let parent = try await recorder.client.newSession(NewSessionParams(agentID: "fake", cwd: harness.root.path))
        let started = try await start(recorder.client, parent: parent.id, key: "result")
        #expect(!started.isError, "\(started.text)")
        let task = try #require(try await recorder.client.tasks().first)
        let child = try #require(task.sessionID)
        let original = try await recorder.client.callTool(
            CallToolParams(
                sessionID: parent.id, tool: "wait_for_task",
                arguments: .object(["task_id": .string(task.id)])))
        #expect(original.structuredContent?["original_result"]?["reply"]?.stringValue == "echo: hello")
        try await recorder.client.attach(child)
        _ = try await recorder.client.prompt(PromptParams(sessionID: child, text: "later"))
        try await recorder.wait("follow-up") { await $0.turnsEnded(child).count >= 2 }
        let current = try await recorder.client.callTool(
            CallToolParams(sessionID: parent.id, tool: "get_task", arguments: .object(["task_id": .string(task.id)])))
        #expect(current.structuredContent?["reply"]?.stringValue == "echo: later")
        #expect(current.structuredContent?["original_result"] == original.structuredContent?["original_result"])
        await recorder.stop()
    }

    @Test func queuedFollowUpCannotReplaceOriginalResult() async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        try harness.start()
        let recorder = try await harness.connect()
        let parent = try await recorder.client.newSession(NewSessionParams(agentID: "fake", cwd: harness.root.path))
        _ = try await start(recorder.client, parent: parent.id, key: "queued", prompt: "slow 3")
        let task = try #require(try await recorder.client.tasks().first)
        let child = try #require(task.sessionID)
        try await recorder.client.attach(child)
        _ = try await recorder.client.prompt(PromptParams(sessionID: child, text: "later", behavior: .queue))
        try await recorder.wait("both turns") { await $0.turnsEnded(child).count >= 2 }
        let result = try await recorder.client.callTool(
            CallToolParams(sessionID: parent.id, tool: "get_task", arguments: .object(["task_id": .string(task.id)])))
        #expect(result.structuredContent?["reply"]?.stringValue == "echo: later")
        #expect(result.structuredContent?["original_result"]?["reply"]?.stringValue?.contains("tick 3") == true)
        await recorder.stop()
    }

    @Test func stopDuringAdmissionNeverPromptsTheChild() async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        let gate = harness.root.appending(path: "release-config")
        harness.agentEnvironment["FAKE_AGENT_CONFIG_GATE"] = gate.path
        try harness.start()
        let recorder = try await harness.connect()
        let parent = try await recorder.client.newSession(NewSessionParams(agentID: "fake", cwd: harness.root.path))
        let flight = Task { try await start(recorder.client, parent: parent.id, key: "stopped", model: "beta") }
        try await recorder.wait("child config gate") { _ in harness.received.contains("config-pending\tmodel=beta") }
        try await recorder.client.cancel(parent.id)
        try Data().write(to: gate)
        let result = try await flight.value
        #expect(result.isError)
        #expect(result.text.contains("stopped"))
        #expect(!harness.received.contains { $0.hasPrefix("prompt\t") })
        #expect(try await recorder.client.tasks().isEmpty)
        let replay = try await start(recorder.client, parent: parent.id, key: "stopped", model: "beta")
        #expect(replay.isError)
        #expect(try await recorder.client.tasks().isEmpty)
        let late = try await start(recorder.client, parent: parent.id, key: "late")
        #expect(late.isError, "A late request must not lift Stop's queue pause")
        #expect(try await recorder.client.tasks().isEmpty)
        _ = try await recorder.client.prompt(PromptParams(sessionID: parent.id, text: "resume"))
        let resumed = try await start(recorder.client, parent: parent.id, key: "late")
        #expect(!resumed.isError, "An explicit user prompt can resume delegation: \(resumed.text)")
        await recorder.stop()
    }
}
#endif
