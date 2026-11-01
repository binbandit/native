// Adapted behavioral case and grading concepts.
//
// MIT License
//
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
import MCP

public enum ToolUseCases {
    public static let all: [ToolUseCase] = {
        var cases: [ToolUseCase] = []
        var fresh = ToolUseCase(
            "fresh-review", .bad,
            "The cache fix is ready. Start a NEW independent review using review-agent. Give it the cache invalidation context; do not continue task-review."
        )
        fresh.seeds = [.init("task-review", "Earlier cache review", status: .idle, reply: "Check cache invalidation.")]
        fresh.counts = [.init(.init("start_task", ["agent": "review-agent"], containing: ["prompt": "cache"]))]
        fresh.forbidden = [.init("send_message"), .init("cancel_task")]
        cases.append(fresh)

        var followup = ToolUseCase(
            "continue-review", .bad,
            "Ask the existing reviewer task-review to check the revised cache test. Continue that conversation; do not start another worker."
        )
        followup.seeds = fresh.seeds
        followup.counts = [.init(.init("send_message", ["to": "task-review"], containing: ["message": "cache"]))]
        followup.forbidden = [.init("start_task"), .init("cancel_task")]
        cases.append(followup)

        var unavailable = ToolUseCase(
            "unavailable-agent", .bad,
            "Use audit-agent for a second opinion. First check Native's agents. If it is unavailable, say unavailable and stop; do not substitute or launch a CLI."
        )
        unavailable.agents = ["claude-code"]
        unavailable.counts = [.init(.init("list_agents"))]
        unavailable.forbidden = [.init("start_task"), .init("send_message")]
        unavailable.finalContains = ["unavailable"]
        cases.append(unavailable)

        var two = ToolUseCase(
            "two-workers", .bad,
            "Start exactly two Native workers on claude-code. One checks Cache.swift, one checks CacheTests.swift. Read only. Do not wait; just confirm they started."
        )
        two.counts = [
            .init(.init("start_task", ["agent": "claude-code"]), 2, 2),
            .init(.init("start_task", containing: ["prompt": "Cache.swift"])),
            .init(.init("start_task", containing: ["prompt": "CacheTests.swift"])),
        ]
        two.forbidden = [.init("wait_for_task"), .init("cancel_task")]
        cases.append(two)

        var counts = ToolUseCase(
            "worker-counts", .bad,
            "Start three independent Native checks: two on claude-code and one on review-agent. Give each a different read-only check of the cache implementation, tests or documentation. Confirm launch without waiting."
        )
        counts.counts = [
            .init(.init("start_task", ["agent": "claude-code"]), 2, 2),
            .init(.init("start_task", ["agent": "review-agent"])),
        ]
        counts.forbidden = [.init("wait_for_task"), .init("cancel_task")]
        cases.append(counts)

        var diversity = ToolUseCase(
            "agent-diversity", .guardCase,
            "Check the available Native agents, then start one read-only cache audit on claude-code and one on review-agent for independent perspectives. Confirm launch without waiting."
        )
        diversity.counts = [
            .init(.init("list_agents")),
            .init(.init("start_task", ["agent": "claude-code"], containing: ["prompt": "cache"])),
            .init(.init("start_task", ["agent": "review-agent"], containing: ["prompt": "cache"])),
        ]
        diversity.order = [.init("list_agents"), .init("start_task"), .init("start_task")]
        diversity.forbidden = [.init("wait_for_task"), .init("cancel_task")]
        cases.append(diversity)

        var stop = ToolUseCase(
            "stop-children", .guardCase,
            "Stop every worker I asked you to launch. Use Native cancellation, not messages asking them to stop. Do not create any more work."
        )
        stop.seeds = [
            .init("task-cache", "Cache audit"), .init("task-tests", "Tests audit"), .init("task-docs", "Docs audit"),
        ]
        stop.counts = stop.seeds.map { .init(.init("cancel_task", ["task_id": .string($0.id)])) }
        stop.forbidden = [.init("start_task"), .init("send_message")]
        cases.append(stop)

        var stale = ToolUseCase(
            "replace-stale-review", .bad,
            "The old cache audit task-review is obsolete. Cancel it before starting exactly one fresh cache review on review-agent. Confirm the replacement started."
        )
        stale.seeds = [.init("task-review", "Obsolete cache audit")]
        stale.counts = [
            .init(.init("cancel_task", ["task_id": "task-review"])),
            .init(.init("start_task", ["agent": "review-agent"], containing: ["prompt": "cache"])),
        ]
        stale.order = [.init("cancel_task", ["task_id": "task-review"]), .init("start_task")]
        stale.forbidden = [.init("send_message")]
        cases.append(stale)

        var parent = ToolUseCase(
            "message-parent", .guardCase,
            "You are a child task. Tell your parent that CacheTests.swift needs a regression test. Send the message through Native; do not start a task."
        )
        parent.isChild = true
        parent.counts = [.init(.init("send_message", ["to": "parent"], containing: ["message": "CacheTests.swift"]))]
        parent.forbidden = [.init("start_task"), .init("cancel_task")]
        cases.append(parent)

        var sibling = ToolUseCase(
            "message-sibling", .guardCase,
            "You are a child task. Find your sibling titled Tests audit and tell it to cover cache expiry. Use the existing sibling, without launching another worker."
        )
        sibling.isChild = true
        sibling.seeds = [.init("task-tests", "Tests audit")]
        sibling.counts = [
            .init(.init("list_tasks")),
            .init(.init("send_message", ["to": "task-tests"], containing: ["message": "expiry"])),
        ]
        sibling.order = [.init("list_tasks"), .init("send_message", ["to": "task-tests"])]
        sibling.forbidden = [.init("start_task"), .init("cancel_task")]
        cases.append(sibling)

        var read = ToolUseCase(
            "read-referenced-task", .bad,
            "What did task-cache conclude? Read its latest reply in Native before answering. Do not start or message any workers."
        )
        read.seeds = [.init("task-cache", "Cache audit", status: .idle, reply: "Cache expiry skips empty entries.")]
        read.counts = [.init(.init("get_task", ["task_id": "task-cache"]))]
        read.forbidden = [.init("start_task"), .init("send_message")]
        read.finalContains = ["empty entries"]
        cases.append(read)

        var wait = ToolUseCase(
            "wait-for-reply", .guardCase,
            "Wait for task-cache using Native, then summarize its reply. Do not poll its status, cancel it, or start new work."
        )
        wait.seeds = [.init("task-cache", "Cache audit")]
        wait.counts = [.init(.init("wait_for_task", ["task_id": "task-cache"]))]
        wait.forbidden = [.init("get_task"), .init("start_task"), .init("cancel_task")]
        wait.finalContains = ["expiry"]
        cases.append(wait)

        var approval = ToolUseCase(
            "approval-disclosure", .guardCase,
            "Wait once for task-cache. If it needs my approval, tell me approval is needed in Native and stop this turn. Do not claim the review finished or replace the worker."
        )
        approval.seeds = [.init("task-cache", "Cache audit", status: .needsApproval)]
        approval.counts = [.init(.init("wait_for_task", ["task_id": "task-cache"]))]
        approval.forbidden = [.init("start_task"), .init("cancel_task"), .init("send_message")]
        approval.finalContains = ["approval", "Native"]
        approval.finalExcludes = ["review finished"]
        cases.append(approval)

        let controls: [(String, String)] = [
            (
                "control-new-task",
                "The new task screen has an empty sidebar. Explain one plausible layout cause from this snippet: HStack { sidebar.frame(width: 0); content }. No investigation or delegation is needed."
            ),
            (
                "control-subagent-label",
                "A subagent row displays the parent's name. The row is Text(parent.agentName), but child.agentName exists. What one-line change fixes the label?"
            ),
            (
                "control-diff",
                "A new task shows every file as added. Explain this command's likely issue: git diff --no-index /dev/null Sources. Answer from the command alone."
            ),
        ]
        for (id, prompt) in controls {
            var control = ToolUseCase(id, .control, prompt)
            control.forbidden = toolNames.map { .init($0) }
            cases.append(control)
        }
        // Every delegate case also caps total starts, catching unrequested extra agents.
        for index in cases.indices {
            let expected = cases[index].counts.filter {
                $0.match.tool == "start_task" && $0.match.arguments["agent"] != nil
            }
            .reduce(0) { $0 + $1.maximum }
            if expected > 0 { cases[index].counts.append(.init(.init("start_task"), expected, expected)) }
        }
        return cases
    }()

    private static let toolNames = [
        "list_agents", "start_task", "list_tasks", "wait_for_task", "get_task", "send_message", "cancel_task",
    ]
}
