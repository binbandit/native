import Foundation

/// Built-in feature descriptions in Settings. Plugin-provided descriptions stay with their manifest.
enum SettingsFeatureCopy {
    static func content(for id: String) -> SettingsPlainlyCopy? {
        switch id {
        case "on-device-titles":
            .init(
                title: "On-device titles",
                description:
                    "Names each task from your first message, privately, with Apple Intelligence. When off, tasks keep the title their agent gives them."
            )
        case SoundsPlugin.id:
            .init(title: "Sounds", description: "A sound when a task finishes, needs you, or fails.")
        case OrchestrationPlugin.id:
            .init(
                title: "Orchestration",
                description: "Lets one agent hand work to another, like Claude Code asking Codex for a review.")
        case MCPServersPlugin.id:
            .init(title: "MCP servers", description: "Set a server up once and every agent gets it.")
        case SkillsPlugin.id:
            .init(
                title: "Skills",
                description: "One list of skills for every agent. Turn them on or off, or install more.")
        case "usage":
            .init(title: "Usage", description: "Warns before a usage limit and picks tasks back up when it resets.")
        case "automation":
            .init(
                title: "Goals and workflows",
                description: "Keep an agent on a goal across turns, or run plan, build and review as one workflow.")
        case "automations":
            .init(
                title: "Automations",
                description: "Starts tasks on a schedule, or when CI fails or a pull request changes.")
        case "expeditions":
            .init(
                title: "Expeditions",
                description: "Several agents take a big goal from plan to pull request, with you approving each step.")
        case "search":
            .init(title: "Search", description: "Find any task by what was said in it. The index stays on this Mac.")
        default: nil
        }
    }
}
