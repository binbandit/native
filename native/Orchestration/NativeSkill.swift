import Foundation

/// A guide Native gives agents for working with Native itself, such as setting it up or writing a
/// plugin, served by the `native` MCP server's `list_skills` and `get_skill` tools. Each skill is a
/// Markdown file in the app's resources, linked to the doc it is (`set-up-native` to
/// `docs/setup.md`, `build-a-native-plugin` to `docs/plugins.md`), so the two can't drift apart.
nonisolated struct NativeSkill: Sendable, Identifiable {
    let id: String
    let title: String
    /// What the skill is for, so an agent can tell whether to read it.
    let summary: String
    let content: String

    /// The skills shipped with the app, by resource name.
    static func bundled(in bundle: Bundle = .main) -> [NativeSkill] {
        ["set-up-native", "build-a-native-plugin"].compactMap { id in
            bundle.url(forResource: id, withExtension: "md")
                .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
                .map { NativeSkill(id: id, markdown: $0) }
        }
    }

    /// Takes the title from the first heading and the summary from the paragraph after it, the
    /// way the docs open.
    init(id: String, markdown: String) {
        self.id = id
        content = markdown
        let lines = markdown.components(separatedBy: .newlines)
        let heading = lines.firstIndex { $0.hasPrefix("# ") }
        title = heading.map { String(lines[$0].dropFirst(2)) } ?? id
        let rest = lines[(heading.map { $0 + 1 } ?? 0)...].drop { $0.trimmingCharacters(in: .whitespaces).isEmpty }
        summary = rest.prefix { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: " ")
    }
}
