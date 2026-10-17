import Foundation
import MCP

/// `list_skills` and `get_skill`: how agents learn to extend Native. Tools rather than MCP
/// resources or prompts, because every agent surfaces tools to its model, and not all do the others.
enum SkillTools {
    static func all(_ skills: [NativeSkill], pluginsFolder: URL) -> [MCPTool<OrchestrationCaller>] {
        guard !skills.isEmpty else { return [] }
        let ids = skills.map(\.id)
        return [
            MCPTool(
                name: "list_skills",
                title: "List skills",
                description: """
                    List Native's skills: guides for extending Native itself, such as building a Native \
                    plugin that adds an agent, an MCP server or a workflow. Read one with get_skill before \
                    doing what it covers.
                    """,
                inputSchema: ["type": "object", "properties": [:], "additionalProperties": false],
                outputSchema: [
                    "type": "object",
                    "properties": [
                        "skills": [
                            "type": "array",
                            "items": [
                                "type": "object",
                                "properties": ["id": ["type": "string"], "title": ["type": "string"], "summary": ["type": "string"]],
                                "required": ["id", "title", "summary"],
                            ],
                        ]
                    ],
                    "required": ["skills"],
                ],
                annotations: MCPToolAnnotations(readOnly: true, openWorld: false),
                arguments: NoSkillArguments.self
            ) { _, _ in
                let lines = skills.map { "- \($0.id): \($0.title). \($0.summary)" }
                let structured = skills.map { JSON.object(["id": .string($0.id), "title": .string($0.title), "summary": .string($0.summary)]) }
                return MCPToolResult(text: "Native's skills (read one with get_skill):\n" + lines.joined(separator: "\n"), structuredContent: ["skills": .array(structured)])
            },
            MCPTool(
                name: "get_skill",
                title: "Get skill",
                description: "Read one of Native's skills in full, such as build-a-native-plugin before writing a Native plugin for the user.",
                inputSchema: [
                    "type": "object",
                    "properties": ["skill": ["type": "string", "enum": .array(ids.map(JSON.string)), "description": "The skill's id, from list_skills."]],
                    "required": ["skill"],
                    "additionalProperties": false,
                ],
                annotations: MCPToolAnnotations(readOnly: true, openWorld: false),
                arguments: SkillArguments.self
            ) { _, arguments in
                guard let skill = skills.first(where: { $0.id == arguments.skill }) else {
                    throw MCPToolError("There's no skill \"\(arguments.skill)\". Skills: \(ids.joined(separator: ", ")).")
                }
                // The folder this copy of Native reads, which isn't always the default.
                let local = "\n\n## On this Mac\n\nNative reads plugins from `\(pluginsFolder.path(percentEncoded: false))`. Write plugins there."
                return MCPToolResult(text: skill.content + (skill.id == "build-a-native-plugin" ? local : ""))
            },
        ]
    }
}

private nonisolated struct NoSkillArguments: Decodable, Sendable {}

private nonisolated struct SkillArguments: Decodable, Sendable {
    var skill: String
}
