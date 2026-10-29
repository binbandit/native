#if DEBUG
import ACP
import Foundation

/// Task Settings' states, from the options real adapters send: codex-acp 2.2.2 (as in
/// `ConfigChoicesTests.loaded`), claude-agent-acp 0.93.0 without a gateway (its six models), and the
/// same adapter with a gateway's list (`GatewayWire`, cut to its first entries and Haiku 5.5).
enum ComposerSettingsPreviewFixtures {
    static func codex(model: String = "gpt-6.1-sol", mode: String = "workspace-write") -> ComposerSettings {
        ComposerSettings(
            ComposerPreviewFixtures.decode(
                """
                [
                  {"id":"mode","name":"Mode","category":"mode","type":"select","currentValue":"\(mode)","options":[
                    {"value":"read-only","name":"Read-only"},{"value":"workspace-write","name":"Workspace access"},
                    {"value":"agent","name":"Auto review"},{"value":"agent-full-access","name":"Full access"}]},
                  {"id":"collaboration_mode","name":"Collaboration mode","category":"collaboration_mode","type":"select","currentValue":"default","options":[
                    {"value":"default","name":"Default"},{"value":"plan","name":"Plan"}]},
                  {"id":"model","name":"Model","category":"model","type":"select","currentValue":"\(model)","options":[
                    {"value":"gpt-6.1-sol","name":"6.1 Sol"},{"value":"gpt-6-astra","name":"6 Astra"},{"value":"gpt-6-sol","name":"6 Sol"},
                    {"value":"gpt-6-luna","name":"6 Luna"},{"value":"gpt-5.6-sol","name":"5.6 Sol"}]},
                  {"id":"reasoning_effort","name":"Reasoning effort","category":"thought_level","type":"select","currentValue":"medium","options":[
                    {"value":"low","name":"Low"},{"value":"medium","name":"Medium"},{"value":"high","name":"High"},
                    {"value":"xhigh","name":"Xhigh"},{"value":"max","name":"Max"},{"value":"ultra","name":"Ultra"}]},
                  {"id":"fast-mode","name":"Fast mode","category":"model_config","type":"select","currentValue":"off","options":[
                    {"value":"off","name":"Off"},{"value":"on","name":"On"}]}
                ]
                """)?.map { CodexConfigOverrides.permissionMapping.presenting($0) } ?? [])
    }

    static func claude(mode: String = "acceptEdits", models: String = claudeModels) -> ComposerSettings {
        ComposerSettings(
            ComposerPreviewFixtures.decode(
                """
                [
                  {"id":"mode","name":"Mode","category":"mode","type":"select","currentValue":"\(mode)","options":[
                    {"value":"default","name":"Manual","description":"Always ask before making changes"},
                    {"value":"acceptEdits","name":"Accept edits","description":"Automatically accept all file edits"},
                    {"value":"plan","name":"Plan","description":"Create a plan before making changes"},
                    {"value":"auto","name":"Auto","description":"Claude handles permission decisions"},
                    {"value":"bypassPermissions","name":"Bypass permissions","description":"Accepts all permissions"}]},
                  {"id":"model","name":"Model","category":"model","type":"select","currentValue":"haiku","options":[\(models)]},
                  {"id":"effort","name":"Effort","category":"thought_level","type":"select","currentValue":"low","options":[
                    {"value":"default","name":"Default"},{"value":"low","name":"Low"},{"value":"medium","name":"Medium"},
                    {"value":"high","name":"High"},{"value":"xhigh","name":"Xhigh"},{"value":"max","name":"Max"}]}
                ]
                """)?.map { ClaudeCodeSessionSettings.permissionMapping.presenting($0) } ?? [])
    }

    static let claudeModels = """
        {"value":"default","name":"Default (recommended)","description":"Opus 5.5"},
        {"value":"opus","name":"Opus 5.5","description":"Opus 5.5 · Best for everyday, complex tasks · $4/$20 per Mtok"},
        {"value":"sonnet","name":"Sonnet 5.5","description":"Sonnet 5.5 · Efficient for routine tasks · $2/$10 per Mtok"},
        {"value":"claude-fable-5","name":"Fable 5"},
        {"value":"claude-fable-5-1","name":"Fable 5.1"},
        {"value":"haiku","name":"Haiku 5.5","description":"Haiku 5.5 · Fastest for quick answers · $1/$5 per Mtok"}
        """

    /// The gateway's list as Claude Code sends it, in its order: its own models, then the gateway's.
    static let gatewayModels =
        claudeModels.replacingOccurrences(of: "\n", with: "") + ","
        + [
            ("claude-fable-5-dd-5.4-ukiah-edualc/tolipoc", "Claude Haiku 4.5"),
            ("claude-fable-5-dd-weiver-otua-xedoc", "Codex Auto Review"),
            ("claude-fable-5-dd-o4-tpg/tolipoc", "GPT-4o"),
            ("claude-fable-5-dd-weiverp-o-4-tpg/tolipoc", "GPT-4o"),
            ("claude-sonnet-4-5-20250929", "Claude 4.5 Sonnet"),
            ("claude-sonnet-4-6", "Claude 4.6 Sonnet"),
            ("claude-sonnet-5", "Claude Sonnet 5"),
            ("claude-opus-5", "Claude Opus 5"),
        ].map { #"{"value":"\#($0.0)","name":"\#($0.1)","description":"From gateway"}"# }.joined(separator: ",")

    static func rows(
        mode: String = "Build", mcp: String = "4", failed: String? = nil, agent: Bool = true
    )
        -> [ComposerSettingsTaskRow]
    {
        var rows = [
            ComposerSettingsTaskRow(
                id: "mode", title: "Mode", value: mode,
                kind: .menu(
                    ["Build", "Plan", "Ask", "Debug", "Review"].map {
                        .init(id: $0.lowercased(), name: $0, isCurrent: $0 == mode)
                    }, commands: [.init(title: "Edit Modes…") {}])
            ) { _ in },
            ComposerSettingsTaskRow(id: "goal", title: "Goal", value: "None", isValueQuiet: true, kind: .page) { _ in },
            ComposerSettingsTaskRow(id: "mcp", title: "MCP servers", value: mcp, failure: failed, kind: .page) { _ in },
        ]
        if agent {
            rows.append(
                ComposerSettingsTaskRow(
                    id: "agent", title: "Agent", value: "Default",
                    kind: .menu(
                        [
                            .init(id: "default", name: "Default", isCurrent: true),
                            .init(id: "reviewer", name: "Reviewer", isCurrent: false),
                        ],
                        commands: [])
                ) { _ in })
        }
        return rows
    }
}
#endif
