import Foundation
import MCP
import NativeSetup

/// `setup_status`: how Native is set up on the caller's Mac (its build, agents, durable host,
/// paired devices, managed settings and updates), so an agent setting Native up for the user, as
/// the `set-up-native` skill describes, can diagnose instead of guess. Read-only.
enum SetupTools {
    /// Follows the orchestration server's own instructions.
    static let instructions =
        " To set Native up for the user, or to find out why part of it isn't working, call setup_status"
        + " and read the set-up-native skill with get_skill."

    static func all(
        report: @escaping @Sendable (OrchestrationCaller) async throws -> SetupReport
    ) -> [MCPTool<OrchestrationCaller>] {
        [
            MCPTool(
                name: "setup_status",
                title: "Setup status",
                description: """
                    Check how Native is set up on this Mac, in order: Native's version and channel; each \
                    agent (installed, turned on, signed in, the version it reports, how it's launched and \
                    installed); the durable host that keeps agents running after Native quits; paired \
                    devices (the iPhone companion) and whether the pairing gateway is listening; which \
                    settings the organization manages; and updates. Each problem says where the user fixes \
                    it in Settings. Read-only: it changes nothing, and reports no paths, secrets or \
                    transcripts. Call it before giving setup advice, and again after the user changes \
                    something.
                    """,
                inputSchema: ["type": "object", "properties": [:], "additionalProperties": false],
                outputSchema: outputSchema,
                annotations: MCPToolAnnotations(readOnly: true, openWorld: false),
                arguments: NoSetupArguments.self
            ) { caller, _ in
                let report = try await report(caller)
                return MCPToolResult(
                    text: report.summary, structuredContent: try JSONDecoder().decode(JSON.self, from: report.encoded())
                )
            }
        ]
    }

    private static let outputSchema: JSON = [
        "type": "object",
        "properties": [
            "native": [
                "type": "object",
                "properties": [
                    "version": ["type": "string"], "build": ["type": "string"],
                    "channel": ["type": "string", "enum": ["stable", "beta", "nightly", "dev"]],
                ],
            ],
            "agents": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "id": ["type": "string"], "name": ["type": "string"],
                        "state": [
                            "type": "string",
                            "enum": ["ready", "starting", "stopped", "not_installed", "turned_off", "not_allowed"],
                        ],
                        "sign_in": [
                            "type": "string", "enum": ["signed_in", "needs_sign_in", "signing_in", "unknown"],
                        ],
                        "launch": ["type": "string"], "version": ["type": "string"],
                        "missing_command": ["type": "string"], "install_command": ["type": "string"],
                        "sign_in_command": ["type": "string"], "is_caller": ["type": "boolean"],
                    ],
                    "required": ["id", "name", "state", "sign_in", "launch", "is_caller"],
                ],
            ],
            "durable_host": ["type": "object"],
            "paired_devices": ["type": "object"],
            "organization": [
                "type": "object",
                "properties": [
                    "managed_keys": ["type": "array", "items": ["type": "string"]],
                    "ignored_keys": ["type": "array", "items": ["type": "string"]],
                ],
            ],
            "updates": ["type": "object"],
        ],
        "required": ["native", "agents", "durable_host", "paired_devices", "organization", "updates"],
    ]
}

extension Orchestrator {
    /// The report for `caller`'s Mac, marking the agent it runs on.
    func setupReport(for caller: OrchestrationCaller) async throws -> SetupReport {
        guard let host else { throw MCPToolError("Native isn't ready yet. Try again shortly.") }
        return await host.setupReport(callerAgent: caller.agent)
    }
}

private nonisolated struct NoSetupArguments: Decodable, Sendable {}
