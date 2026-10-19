import ACP
import Foundation
import Modes

/// Config options captured from the bundled adapters, trimmed to what modes read.
enum Fixtures {
    /// codex-acp 2.2.2's `session/load` result (captured 2026-10-18), descriptions trimmed. Plan
    /// Mode is a setting of its own; the permission mode has a read-only level.
    static let codex = #"""
        [
          {"id":"mode","name":"Mode","category":"mode","type":"select","currentValue":"agent","options":[
            {"value":"read-only","name":"Read-only"},{"value":"workspace-write","name":"Workspace access"},
            {"value":"agent","name":"Auto review"},{"value":"agent-full-access","name":"Full access"}]},
          {"id":"collaboration_mode","name":"Collaboration mode","category":"collaboration_mode","type":"select","currentValue":"default","options":[
            {"value":"default","name":"Default"},{"value":"plan","name":"Plan"}]},
          {"id":"model","name":"Model","category":"model","type":"select","currentValue":"gpt-6-astra","options":[
            {"value":"gpt-6.1-sol","name":"6.1 Sol"},{"value":"gpt-6-astra","name":"6 Astra"},{"value":"gpt-6-sol","name":"6 Sol"}]},
          {"id":"reasoning_effort","name":"Reasoning effort","category":"thought_level","type":"select","currentValue":"xhigh","options":[
            {"value":"low","name":"Low"},{"value":"medium","name":"Medium"},{"value":"high","name":"High"},
            {"value":"xhigh","name":"Xhigh"}]}
        ]
        """#

    /// claude-agent-acp 0.93.0's `session/new` result (the model list cut to two). Plan Mode is a
    /// permission mode, and there's no read-only level.
    static let claudeCode = #"""
        [
          {"id":"mode","name":"Mode","category":"mode","type":"select","currentValue":"acceptEdits","options":[
            {"value":"default","name":"Manual"},{"value":"acceptEdits","name":"Accept edits"},{"value":"plan","name":"Plan"},
            {"value":"auto","name":"Auto"},{"value":"dontAsk","name":"Don't ask"},{"value":"bypassPermissions","name":"Bypass permissions"}]},
          {"id":"model","name":"Model","category":"model","type":"select","currentValue":"opus","options":[
            {"value":"default","name":"Default (recommended)"},{"value":"opus","name":"Opus 5.5"}]},
          {"id":"effort","name":"Effort","category":"thought_level","type":"select","currentValue":"xhigh","options":[
            {"value":"low","name":"Low"},{"value":"high","name":"High"},{"value":"xhigh","name":"Xhigh"}]}
        ]
        """#

    /// An agent Native knows nothing about: two levels, no plan mode, no read-only.
    static let unknown = #"""
        [
          {"id":"approvals","name":"Approvals","category":"mode","type":"select","currentValue":"code","options":[
            {"value":"careful","name":"Careful"},{"value":"code","name":"Code"}]}
        ]
        """#

    static func options(_ json: String) throws -> [ConfigOption] {
        try JSONDecoder().decode([ConfigOption].self, from: Data(json.utf8))
    }

    /// The options with `id` set to `value`, as the agent would report after a change.
    static func setting(_ options: [ConfigOption], _ id: String, to value: String) -> [ConfigOption] {
        options.map { option in
            guard option.id == id, case .select(_, let choices) = option.kind else { return option }
            var changed = option
            changed.kind = .select(currentValue: value, options: choices)
            return changed
        }
    }

    static func applying(_ changes: [ModeResolution.Change], to options: [ConfigOption]) -> [ConfigOption] {
        changes.reduce(options) { setting($0, $1.optionID, to: $1.value) }
    }

    static func current(_ id: String, in options: [ConfigOption]) -> String? {
        guard case .select(let current, _)? = options.first(where: { $0.id == id })?.kind else { return nil }
        return current
    }
}
