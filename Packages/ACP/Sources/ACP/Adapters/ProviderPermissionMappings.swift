extension ClaudeCodeSessionSettings {
    /// claude-agent-acp 0.93.0 permissionMode values, selected by the provider plugin.
    public static var permissionMapping: TaskPermissionMapping {
        .init(values: [
            .askFirst: ["default"], .acceptEdits: ["acceptEdits"],
            .auto: ["auto"], .fullAccess: ["bypassPermissions"],
        ])
    }
}

extension CodexConfigOverrides {
    /// codex-acp 2.2.2: workspace-write uses on-request and the user reviewer; agent uses
    /// on-request and auto_review; agent-full-access uses never and danger-full-access.
    public static var permissionMapping: TaskPermissionMapping {
        .init(
            values: [
                .askFirst: ["workspace-write", "read-only"],
                .auto: ["agent"], .fullAccess: ["agent-full-access"],
            ], notes: [.askFirst: "Workspace edits and commands are allowed; outside access asks."])
    }
}
