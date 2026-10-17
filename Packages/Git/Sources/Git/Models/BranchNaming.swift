import Foundation

/// Names for task branches. A task's branch has to exist before its agent session starts, but its
/// good name only comes from the first prompt, so it starts as `<prefix><code>` and is renamed
/// from the task's title later, as the reference app does with its placeholder branches.
public enum BranchNaming {
    /// Characters of a provisional code; the last is a digit so it never reads as a word.
    static let codeLength = 5

    /// A prefix as the user typed it, made safe to put in front of a branch name: `brayden/`,
    /// `team/brayden/`, or empty.
    public static func normalizedPrefix(_ raw: String) -> String {
        let segments = raw.split(separator: "/").map { Worktree.slug(String($0), maxLength: 40) }.filter { $0 != "task" || raw.contains("task") }
        return segments.isEmpty ? "" : segments.joined(separator: "/") + "/"
    }

    /// A random code such as `k3f9x2`'s shape: lowercase letters and digits, ending in a digit.
    public static func provisionalCode(using generator: inout some RandomNumberGenerator) -> String {
        let characters = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        let digits = Array("0123456789")
        var code = (0..<(codeLength - 1)).map { _ in characters.randomElement(using: &generator) ?? "a" }
        code.append(digits.randomElement(using: &generator) ?? "0")
        return String(code)
    }

    public static func provisionalCode() -> String {
        var generator = SystemRandomNumberGenerator()
        return provisionalCode(using: &generator)
    }

    /// The branch name for a task titled `title`: the prefix, then the title in kebab case.
    public static func name(forTitle title: String, prefix: String) -> String {
        prefix + Worktree.slug(title, maxLength: 40)
    }

    /// The prefix of a provisional name, which renaming keeps.
    static func prefix(ofProvisional name: String) -> String {
        String(name.dropLast(codeLength))
    }
}
