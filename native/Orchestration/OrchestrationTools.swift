import Foundation
import MCP

/// The tools agents use to hand each other tasks and talk to each other. Their names, descriptions
/// and schemas are the API models read, so they say when to use each tool as much as what it does.
enum OrchestrationTools {
    static let instructions = """
        Native runs several coding agents side by side. These tools let you hand work to another agent \
        session, such as Codex for a second opinion or another session of your own agent for a parallel \
        subtask, and work with it: start_task, then wait_for_task for its reply; send_message to follow \
        up or to talk to related tasks; cancel_task to stop one. Tasks work in the same project \
        directory as you, and the user sees each one as a subagent of the session that started it. If \
        you are a task yourself, list_tasks shows your parent and sibling tasks, which you can message. \
        Delegate work that benefits from an independent session or a different model; do quick lookups \
        yourself. To extend Native itself, such as writing a Native plugin for the user, read the guide \
        first: list_skills, then get_skill.
        """

    private static let taskID: JSON = [
        "type": "string",
        "description": "A task id from start_task or list_tasks, or \"parent\" for the session that started you.",
    ]

    static func all(_ orchestrator: Orchestrator) -> [MCPTool<OrchestrationCaller>] {
        [
            MCPTool(
                name: "list_agents",
                title: "List agents",
                description: "List the coding agents you can hand tasks to with start_task, such as Claude Code and Codex. Each task runs as its own session of that agent, which the user can watch in Native.",
                inputSchema: ["type": "object", "properties": [:], "additionalProperties": false],
                outputSchema: [
                    "type": "object",
                    "properties": ["agents": ["type": "array", "items": [
                        "type": "object",
                        "properties": ["id": ["type": "string"], "name": ["type": "string"], "is_you": ["type": "boolean"]],
                        "required": ["id", "name", "is_you"],
                    ]]],
                    "required": ["agents"],
                ],
                annotations: MCPToolAnnotations(readOnly: true, openWorld: false),
                arguments: NoArguments.self
            ) { caller, _ in
                try await orchestrator.listAgents(for: caller)
            },
            MCPTool(
                name: "start_task",
                title: "Start task",
                description: """
                    Hand a task to a new session of a coding agent and return right away with a task_id; \
                    the task runs in the background while you continue.

                    The new session works in the same project directory as you, with the tools it would \
                    have if the user had started it, but it hasn't seen your conversation: make the prompt \
                    self-contained, with the goal, the relevant files and context, constraints, and what to \
                    report back. Get agent ids from list_agents. You can pick a different agent (for \
                    example Codex, for an independent review) or another session of your own agent.

                    Then call wait_for_task for its reply, send_message to follow up or redirect it, or \
                    cancel_task to stop it. The user sees the task as a subagent of your session and \
                    approves its tool calls. Tasks you start can message each other, so parallel tasks can \
                    coordinate; they share the working directory, so don't give them overlapping files to \
                    edit.
                    """,
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "agent": ["type": "string", "description": "Id of the agent to run the task, from list_agents, such as \"codex\" or \"claude-code\"."],
                        "prompt": ["type": "string", "description": "The task, written for a capable colleague who hasn't seen this conversation."],
                        "title": ["type": "string", "description": "A short title the user sees for the task, in sentence case, like \"Review the auth middleware\"."],
                    ],
                    "required": ["agent", "prompt"],
                    "additionalProperties": false,
                ],
                outputSchema: taskSchema,
                annotations: MCPToolAnnotations(readOnly: false, openWorld: false),
                arguments: StartTaskArguments.self
            ) { caller, arguments in
                try await orchestrator.startTask(agent: arguments.agent, prompt: arguments.prompt, title: arguments.title, for: caller)
            },
            MCPTool(
                name: "list_tasks",
                title: "List tasks",
                description: """
                    List the sessions you can reach, with their status: the tasks you started and, if you \
                    are a task yourself, the session that started you ("parent") and its other tasks (your \
                    siblings). Use it to find who to message, for example a sibling working on a related \
                    part of the same job.
                    """,
                inputSchema: ["type": "object", "properties": [:], "additionalProperties": false],
                outputSchema: [
                    "type": "object",
                    "properties": [
                        "you": ["type": "string", "description": "Your own task id, when you're a task."],
                        "tasks": ["type": "array", "items": [
                            "type": "object",
                            "properties": [
                                "id": ["type": "string"],
                                "agent": ["type": "string"],
                                "title": ["type": "string"],
                                "relation": ["type": "string", "enum": ["parent", "child", "sibling"]],
                                "status": ["type": "string", "enum": ["running", "needs_approval", "idle", "failed", "cancelled", "closed"]],
                            ],
                            "required": ["id", "agent", "relation", "status"],
                        ]],
                    ],
                    "required": ["tasks"],
                ],
                annotations: MCPToolAnnotations(readOnly: true, openWorld: false),
                arguments: NoArguments.self
            ) { caller, _ in
                try await orchestrator.listTasks(for: caller)
            },
            MCPTool(
                name: "wait_for_task",
                title: "Wait for task",
                description: """
                    Wait for a task's current turn to finish, then return its status and its reply: what \
                    the agent said at the end of its latest turn. Works on any session list_tasks shows.

                    Returns early with status needs_approval when the task is blocked on the user \
                    approving one of its tool calls in Native; let the user know if they might not have \
                    noticed, then call wait_for_task again. If the timeout passes first, the status is \
                    running: call wait_for_task again to keep waiting, or do other work and check back.
                    """,
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "task_id": taskID,
                        "timeout_seconds": [
                            "type": "integer",
                            "minimum": 1,
                            "maximum": 240,
                            "description": "The longest to wait, in seconds. Defaults to 120. If the call itself times out before the task finishes, use a lower value.",
                        ],
                    ],
                    "required": ["task_id"],
                    "additionalProperties": false,
                ],
                outputSchema: taskSchema,
                annotations: MCPToolAnnotations(readOnly: true, openWorld: false),
                arguments: WaitArguments.self
            ) { caller, arguments in
                // MCP clients give up on a silent call after a few minutes (Claude Code after five).
                let seconds = min(max(arguments.timeoutSeconds ?? 120, 1), 240)
                return try await orchestrator.waitForTask(arguments.taskID, timeout: .seconds(seconds), for: caller)
            },
            MCPTool(
                name: "get_task",
                title: "Get task",
                description: "Check a task's status and its latest reply without waiting. Works on any session list_tasks shows.",
                inputSchema: [
                    "type": "object",
                    "properties": ["task_id": taskID],
                    "required": ["task_id"],
                    "additionalProperties": false,
                ],
                outputSchema: taskSchema,
                annotations: MCPToolAnnotations(readOnly: true, openWorld: false),
                arguments: TaskArguments.self
            ) { caller, arguments in
                try await orchestrator.getTask(arguments.taskID, for: caller)
            },
            MCPTool(
                name: "send_message",
                title: "Send message",
                description: """
                    Send a message to a task you started, a sibling task, or your parent ("parent"): \
                    follow-up instructions, a correction, a question, or something they need to know. \
                    It's delivered right away: into the turn the recipient is working on, or queued for \
                    its next turn, or, if it's idle, as a new prompt. The recipient sees who it's from and \
                    can answer with send_message. This doesn't wait for a reply; call wait_for_task on the \
                    recipient if you want one.
                    """,
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "to": taskID,
                        "message": ["type": "string", "description": "The message, written so it makes sense without your conversation."],
                    ],
                    "required": ["to", "message"],
                    "additionalProperties": false,
                ],
                outputSchema: [
                    "type": "object",
                    "properties": [
                        "to": ["type": "string"],
                        "delivery": [
                            "type": "string",
                            "enum": ["steered", "queued", "prompted"],
                            "description": "steered: added to its running turn; queued: held for its next turn; prompted: started a turn of the idle recipient.",
                        ],
                    ],
                    "required": ["to", "delivery"],
                ],
                annotations: MCPToolAnnotations(readOnly: false, openWorld: false),
                arguments: MessageArguments.self
            ) { caller, arguments in
                try await orchestrator.sendMessage(to: arguments.to, message: arguments.message, for: caller)
            },
            MCPTool(
                name: "cancel_task",
                title: "Cancel task",
                description: "Stop the current turn of a task you started. Its session stays open, so you can give it new instructions with send_message afterwards.",
                inputSchema: [
                    "type": "object",
                    "properties": ["task_id": ["type": "string", "description": "The task_id start_task returned."]],
                    "required": ["task_id"],
                    "additionalProperties": false,
                ],
                outputSchema: taskSchema,
                annotations: MCPToolAnnotations(readOnly: false, destructive: true, idempotent: true, openWorld: false),
                arguments: TaskArguments.self
            ) { caller, arguments in
                try await orchestrator.cancelTask(arguments.taskID, for: caller)
            },
        ]
    }

    /// What the task tools report, for clients that read the structured result.
    private static let taskSchema: JSON = [
        "type": "object",
        "properties": [
            "task_id": ["type": "string"],
            "agent": ["type": "string", "description": "The id of the agent running the task."],
            "title": ["type": "string"],
            "relation": ["type": "string", "enum": ["parent", "child", "sibling"]],
            "status": ["type": "string", "enum": ["running", "needs_approval", "idle", "failed", "cancelled"]],
            "reply": ["type": "string", "description": "What the agent said at the end of its latest turn; partial while it's running."],
            "detail": ["type": "string", "description": "What it's waiting on approval for, or why it failed or stopped early."],
        ],
        "required": ["task_id", "agent", "relation", "status"],
    ]
}

private nonisolated struct NoArguments: Decodable, Sendable {}

private nonisolated struct StartTaskArguments: Decodable, Sendable {
    var agent: String
    var prompt: String
    var title: String?
}

private nonisolated struct TaskArguments: Decodable, Sendable {
    var taskID: String

    enum CodingKeys: String, CodingKey {
        case taskID = "task_id"
    }
}

private nonisolated struct WaitArguments: Decodable, Sendable {
    var taskID: String
    var timeoutSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case taskID = "task_id"
        case timeoutSeconds = "timeout_seconds"
    }
}

private nonisolated struct MessageArguments: Decodable, Sendable {
    var to: String
    var message: String
}
