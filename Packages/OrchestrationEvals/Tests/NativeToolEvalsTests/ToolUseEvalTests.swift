import Foundation
import MCP
import NativePolicy
import Testing

@testable import NativeToolEvals

@Suite("Native orchestration tool-use evals")
struct ToolUseEvalTests {
    @Test(arguments: ToolUseCases.all)
    func acceptsSupportedBehavior(test: ToolUseCase) async throws {
        let (trace, declarations) = await referenceTrace(test)
        let decoded = try JSONDecoder().decode(EvalTranscript.self, from: JSONEncoder().encode(trace))
        let grade = ToolUseGrader.grade(decoded, against: test, declarations: declarations)
        #expect(grade.outcome == .passed, "\(test.id): \(grade.failures)")
        #expect(trace.calls.allSatisfy { !$0.isError })
    }

    @Test(arguments: ToolUseCases.all.filter { $0.kind != .control })
    func rejectsMissingBehavior(test: ToolUseCase) async {
        let (trace, declarations) = await referenceTrace(test)
        var missing = trace
        missing.calls = []
        #expect(ToolUseGrader.grade(missing, against: test, declarations: declarations).outcome == .failed)
    }

    @Test(arguments: ToolUseCases.all.filter { $0.kind == .control })
    func controlsRejectAccidentalOrchestration(test: ToolUseCase) async {
        let session = EvalSession(test)
        _ = await session.call("list_tasks", arguments: [:])
        let grade = ToolUseGrader.grade(
            await session.trace(finalText: "The row uses the wrong model."), against: test,
            declarations: session.tools.map(\.declaration))
        #expect(grade.outcome == .failed)
        #expect(grade.failures.contains("Forbidden call: list_tasks"))
    }

    @Test func rejectsWrongAgentExtraWorkerAndFailedAttempts() async throws {
        let test = try #require(ToolUseCases.all.first { $0.id == "two-workers" })
        let (trace, declarations) = await referenceTrace(test)
        var wrong = trace
        wrong.calls[0].arguments = ["agent": "review-agent", "prompt": "Cache.swift"]
        #expect(ToolUseGrader.grade(wrong, against: test, declarations: declarations).outcome == .failed)
        var extra = trace
        extra.calls.append(trace.calls[0])
        #expect(ToolUseGrader.grade(extra, against: test, declarations: declarations).outcome == .failed)
        var failed = trace
        failed.calls[0].isError = true
        #expect(ToolUseGrader.grade(failed, against: test, declarations: declarations).outcome == .failed)
        var unobserved = trace
        unobserved.calls[0].result = nil
        #expect(ToolUseGrader.grade(unobserved, against: test, declarations: declarations).outcome == .failed)
        unobserved.calls[0].result = .null
        #expect(ToolUseGrader.grade(unobserved, against: test, declarations: declarations).outcome == .failed)
        unobserved.calls[0].result = ["isError": true]
        #expect(ToolUseGrader.grade(unobserved, against: test, declarations: declarations).outcome == .failed)
    }

    @Test func orderRequiresSeparateSuccessfulCalls() async throws {
        let test = try #require(ToolUseCases.all.first { $0.id == "replace-stale-review" })
        let (trace, declarations) = await referenceTrace(test)
        var reversed = trace
        reversed.calls.reverse()
        #expect(
            ToolUseGrader.grade(reversed, against: test, declarations: declarations).failures.contains {
                $0.contains("ordered")
            })
        var twice = test
        twice.order = [.init("cancel_task"), .init("cancel_task")]
        #expect(ToolUseGrader.grade(trace, against: twice, declarations: declarations).outcome == .failed)
    }

    @Test func resultEvidenceAndFinalAnswerAreSeparate() async throws {
        let test = try #require(ToolUseCases.all.first { $0.id == "read-referenced-task" })
        let (trace, declarations) = await referenceTrace(test)
        #expect(trace.calls[0].result?["structuredContent"]?["reply"] == "Cache expiry skips empty entries.")
        var noEvidence = trace
        noEvidence.finalText = "The cache is correct."
        #expect(ToolUseGrader.grade(noEvidence, against: test, declarations: declarations).outcome == .failed)
        noEvidence.finalText = ""
        #expect(
            ToolUseGrader.grade(noEvidence, against: test, declarations: declarations).failures.contains(
                "Missing final answer"))
    }

    @Test func approvalDoesNotBecomeCompletion() async throws {
        let test = try #require(ToolUseCases.all.first { $0.id == "approval-disclosure" })
        let (trace, declarations) = await referenceTrace(test)
        #expect(trace.calls[0].result?["structuredContent"]?["status"] == "needs_approval")
        var misleading = trace
        misleading.finalText += " The review finished."
        #expect(ToolUseGrader.grade(misleading, against: test, declarations: declarations).outcome == .failed)
    }

    @Test func rejectsWrongRecipientEvenWithCorrectMessage() async throws {
        let test = try #require(ToolUseCases.all.first { $0.id == "message-sibling" })
        let (trace, declarations) = await referenceTrace(test)
        var wrong = trace
        wrong.calls[1].arguments = ["to": "parent", "message": "Cover cache expiry"]
        #expect(ToolUseGrader.grade(wrong, against: test, declarations: declarations).outcome == .failed)
    }

    @Test func distinguishesInfrastructureErrorsFromBehaviorFailures() async throws {
        let test = try #require(ToolUseCases.all.first)
        let (trace, declarations) = await referenceTrace(test)
        var interrupted = trace
        interrupted.completion = .infrastructureError
        #expect(
            ToolUseGrader.grade(interrupted, against: test, declarations: declarations).outcome == .infrastructureError)
        interrupted.completion = .stepLimit
        #expect(ToolUseGrader.grade(interrupted, against: test, declarations: declarations).outcome == .failed)
        interrupted.caseID = "another-case"
        #expect(
            ToolUseGrader.grade(interrupted, against: test, declarations: declarations).outcome == .infrastructureError)
    }

    @Test func rejectsUnsupportedToolShapesBeforeProductionHandler() async throws {
        let test = try #require(ToolUseCases.all.first)
        let session = EvalSession(test)
        for arguments: JSON in [
            ["agent": "claude-code"],
            ["agent": "claude-code", "prompt": "Review", "model": "invented"],
            ["agent": 7, "prompt": "Review"],
        ] {
            #expect(await session.call("start_task", arguments: arguments)["isError"] == true)
        }
        for timeout: JSON in [0, 241, 1.5, "120"] {
            #expect(
                await session.call("wait_for_task", arguments: ["task_id": "task-review", "timeout_seconds": timeout])[
                    "isError"] == true)
        }
        let trace = await session.trace(finalText: "Started.")
        #expect(
            ToolUseGrader.grade(trace, against: test, declarations: session.tools.map(\.declaration)).outcome == .failed
        )
        #expect(await session.call("exec_command", arguments: ["cmd": "echo test"])["isError"] == true)
    }

    @Test func realHandlersEnforceReachabilityAndCancellationOwnership() async throws {
        let test = try #require(ToolUseCases.all.first { $0.id == "message-sibling" })
        let session = EvalSession(test)
        #expect(await session.call("cancel_task", arguments: ["task_id": "task-tests"])["isError"] == true)
        #expect(await session.call("get_task", arguments: ["task_id": "unrelated-task"])["isError"] == true)
        #expect(
            await session.call("send_message", arguments: ["to": "task-tests", "message": "Cover expiry"])["isError"]
                == false)
    }

    @Test func callBudgetIsABehaviorFailure() async throws {
        let test = try #require(ToolUseCases.all.first)
        let session = EvalSession(test, maximumCalls: 1)
        _ = await session.call("list_agents", arguments: [:])
        #expect(await session.call("list_tasks", arguments: [:])["isError"] == true)
        let trace = await session.trace(finalText: "Stopped at budget.")
        #expect(trace.calls.count == 1)
        #expect(trace.completion == .stepLimit)
    }

    @Test func catalogAndSchemasStaySourceBacked() throws {
        #expect(ToolUseCases.all.count == 16)
        #expect(Set(ToolUseCases.all.map(\.id)).count == 16)
        let test = try #require(ToolUseCases.all.first)
        let declarations = EvalSession(test).tools.map(\.declaration)
        let expected: Set<String> = [
            "list_agents", "start_task", "list_tasks", "wait_for_task", "get_task", "send_message", "cancel_task",
        ]
        #expect(Set(declarations.compactMap { $0["name"]?.stringValue }) == expected)
        for declaration in declarations {
            let schema = try #require(declaration["inputSchema"])
            #expect(schema["type"] == "object")
            #expect(schema["additionalProperties"] == false)
            let schemaKeys = Set(schema.objectValue?.keys.map { $0 } ?? [])
            #expect(schemaKeys.isSubset(of: ["type", "properties", "required", "additionalProperties", "description"]))
            for property in (schema["properties"]?.objectValue ?? [:]).values {
                #expect(["string", "integer"].contains(property["type"]?.stringValue ?? ""))
                let keys = Set(property.objectValue?.keys.map { $0 } ?? [])
                #expect(
                    keys.isSubset(of: [
                        "type", "description", "minimum", "maximum", "enum",
                    ]))
            }
        }
    }

    @Test func managedPolicyCanDisableLiveRuns() throws {
        var policy = NativePolicy()
        try EvalLivePolicy.check(policy)
        policy.agents.allowed = []
        #expect(throws: (any Error).self) { try EvalLivePolicy.check(policy) }
        policy = NativePolicy()
        policy.network.mode = .airGapped
        #expect(throws: (any Error).self) { try EvalLivePolicy.check(policy) }
        policy = NativePolicy()
        policy.network.services[.agentProvider] = .init(enabled: false)
        #expect(throws: (any Error).self) { try EvalLivePolicy.check(policy) }
        policy = NativePolicy()
        policy.network.isValid = false
        #expect(throws: (any Error).self) { try EvalLivePolicy.check(policy) }
    }

    private func referenceTrace(_ test: ToolUseCase) async -> (EvalTranscript, [JSON]) {
        let session = EvalSession(test)
        func call(_ tool: String, _ args: JSON = [:]) async { _ = await session.call(tool, arguments: args) }
        switch test.id {
        case "fresh-review": await call("start_task", ["agent": "review-agent", "prompt": "Review cache invalidation"])
        case "continue-review": await call("send_message", ["to": "task-review", "message": "Check the cache test"])
        case "unavailable-agent": await call("list_agents")
        case "two-workers":
            await call("start_task", ["agent": "claude-code", "prompt": "Read Cache.swift"])
            await call("start_task", ["agent": "claude-code", "prompt": "Read CacheTests.swift"])
        case "worker-counts":
            await call("start_task", ["agent": "claude-code", "prompt": "Read cache implementation"])
            await call("start_task", ["agent": "claude-code", "prompt": "Read cache tests"])
            await call("start_task", ["agent": "review-agent", "prompt": "Read cache docs"])
        case "agent-diversity":
            await call("list_agents")
            await call("start_task", ["agent": "claude-code", "prompt": "Review cache"])
            await call("start_task", ["agent": "review-agent", "prompt": "Audit cache"])
        case "stop-children":
            for seed in test.seeds { await call("cancel_task", ["task_id": .string(seed.id)]) }
        case "replace-stale-review":
            await call("cancel_task", ["task_id": "task-review"])
            await call("start_task", ["agent": "review-agent", "prompt": "Review cache"])
        case "message-parent":
            await call("send_message", ["to": "parent", "message": "CacheTests.swift needs a regression test"])
        case "message-sibling":
            await call("list_tasks")
            await call("send_message", ["to": "task-tests", "message": "Cover cache expiry"])
        case "read-referenced-task": await call("get_task", ["task_id": "task-cache"])
        case "wait-for-reply", "approval-disclosure": await call("wait_for_task", ["task_id": "task-cache"])
        default: break
        }
        return (
            await session.trace(finalText: "Started or answered. " + test.finalContains.joined(separator: ". ")),
            session.tools.map(\.declaration)
        )
    }
}
