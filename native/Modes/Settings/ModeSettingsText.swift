import Modes

/// What a mode applies, in a line for its Settings row: "Read-only · Plan Mode · Model gpt-6.1-sol".
enum ModeSettingsText {
    static func describe(_ mode: Mode) -> String {
        let settings = mode.settings
        var parts: [String] = []
        if settings.usesPlanMode { parts.append("Uses the agent's plan mode") }
        if let autonomy = settings.autonomy { parts.append(autonomy.title) }
        if let model = settings.model { parts.append("Model \(model)") }
        if let effort = settings.effort { parts.append("\(effort) effort") }
        if parts.isEmpty {
            return mode.instructions.isEmpty ? "No instructions, and the task's settings as they are" : "Instructions only"
        }
        return parts.joined(separator: " · ")
    }
}
