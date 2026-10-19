import AIInstructions
import Foundation

/// The prompt for drafting a pull request's title and description from a branch's commits and
/// diff. On-device models have small context windows, so the material is trimmed to a budget:
/// commit messages first (they say what was intended), then as much of the diff as fits.
public struct PullRequestDraftPrompt: Sendable, Hashable {
    public var head: String
    public var base: String?
    /// `git log` output for the branch, newest first.
    public var commits: String
    /// `git diff base...head`, if available.
    public var diff: String?
    /// The repository's pull request template, which the description should follow.
    public var template: String?

    public init(head: String, base: String? = nil, commits: String, diff: String? = nil, template: String? = nil) {
        self.head = head
        self.base = base
        self.commits = commits
        self.diff = diff
        self.template = template
    }

    public static let instructions = """
        You write GitHub pull request titles and descriptions from a branch's commits and diff.
        The title is one line under 72 characters, in the imperative mood, without a trailing period. \
        Keep a conventional-commit prefix such as "fix(ui):" if the commits use one.
        The description is GitHub Markdown: open with one or two sentences on what was wrong or \
        missing and why it matters, then explain how the change addresses it. Use a short bullet list \
        only for several distinct changes. Never invent details the commits and diff don't support, \
        and don't mention files that weren't changed.
        """

    /// The instructions with the user's own after them, which never replace the rules above.
    public static func instructions(adding addition: AIInstructionAddition?) -> String {
        AIInstructionAddition.applying(addition, to: instructions)
    }

    /// The prompt, no longer than `characterBudget`.
    public func text(characterBudget: Int) -> String {
        var sections = ["Branch: \(head)" + (base.map { " (into \($0))" } ?? "")]
        if let template = template?.trimmingCharacters(in: .whitespacesAndNewlines), !template.isEmpty {
            sections.append("Follow this pull request template:\n\(Self.trim(template, to: 1_500))")
        }
        let fixed = sections.joined(separator: "\n\n").count
        let remaining = max(characterBudget - fixed - 64, 0)

        let commitText = commits.trimmingCharacters(in: .whitespacesAndNewlines)
        let commitBudget = diff == nil ? remaining : min(commitText.count, remaining / 2)
        sections.append("Commits:\n\(Self.trim(commitText, to: commitBudget))")
        if let diff = diff?.trimmingCharacters(in: .whitespacesAndNewlines), !diff.isEmpty {
            let used = sections.joined(separator: "\n\n").count
            let diffBudget = characterBudget - used - 16
            if diffBudget > 200 {
                sections.append("Diff:\n\(Self.trim(diff, to: diffBudget))")
            }
        }
        return sections.joined(separator: "\n\n")
    }

    /// Cuts at a line break where possible, marking what was left out.
    static func trim(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        let marker = "\n[…truncated]"
        guard limit > marker.count else { return String(text.prefix(max(limit, 0))) }
        let prefix = text.prefix(limit - marker.count)
        let cut = prefix.lastIndex(of: "\n").map { prefix[..<$0] } ?? prefix
        return cut + marker
    }
}
