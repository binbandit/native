import NativeCommands
import SessionTools

/// A row of the well and of Settings ▸ Task Tools. Native's own come first, in key order; tools
/// enabled plugins add (`NativePlugin.sessionTools`) follow, opened and switched the same way.
struct TaskWellTool: Hashable, Identifiable {
    /// Where it can open, saved with the rest of the arrangement (Settings ▸ Task Tools).
    let spec: SessionToolSpec
    let title: String
    let symbol: String
    let command: CommandID
    /// What it is, in a sentence, for Settings ▸ Task Tools.
    let summary: String
    /// The plugin that added it; nil for Native's own.
    var pluginName: String?

    var id: SessionToolID { spec.id }

    static let changes = TaskWellTool(
        spec: .changes, title: "Changes", symbol: "plus.forwardslash.minus", command: .sessionToolChanges,
        summary: "Review and commit what the task changed. In a narrow window it takes the conversation's place.")
    static let terminal = TaskWellTool(
        spec: .terminal, title: "Terminal", symbol: "terminal", command: "taskWell.terminal",
        summary: "A shell in the task's folder, under the composer.")
    static let dev = TaskWellTool(
        spec: .dev, title: "Dev", symbol: "play", command: "taskWell.dev",
        summary: "Your project's actions, such as a dev server, under the composer.")
    static let subagents = TaskWellTool(
        spec: .subagents, title: "Subagents", symbol: "person.2", command: "taskWell.subagents",
        summary: "The task's workers, beside the conversation.")
    static let pullRequest = TaskWellTool(
        spec: .pullRequest, title: "Pull request", symbol: "arrow.triangle.pull", command: "taskWell.pullRequest",
        summary: "The branch's pull request and its checks.")

    /// Native's own, in key order (⌥⌘1 to ⌥⌘5).
    static let builtIns: [TaskWellTool] = [.changes, .terminal, .dev, .subagents, .pullRequest]

    init(
        spec: SessionToolSpec, title: String, symbol: String, command: CommandID, summary: String,
        pluginName: String? = nil
    ) {
        self.spec = spec
        self.title = title
        self.symbol = symbol
        self.command = command
        self.summary = summary
        self.pluginName = pluginName
    }

    /// A plugin's tool. Its command has no default key; Settings ▸ Keyboard Shortcuts assigns one.
    init(_ tool: SessionToolContribution) {
        self.init(
            spec: tool.spec, title: tool.title, symbol: tool.systemImage,
            command: CommandID("sessionTools.\(tool.id.rawValue)"), summary: tool.summary ?? "",
            pluginName: tool.pluginName)
    }
}

extension SessionToolRegistry {
    /// Every tool the well can list, in order: Native's own, then enabled plugins'.
    var wellTools: [TaskWellTool] {
        TaskWellTool.builtIns + pluginTools.map(TaskWellTool.init)
    }
}
