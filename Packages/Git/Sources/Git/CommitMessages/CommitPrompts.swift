import AIInstructions
import Foundation

/// What the on-device model is told when it writes a commit message or splits changes into
/// commits: Native's rules for the repository's style, then the user's own instructions, which add
/// to the rules and never replace them.
public enum CommitPrompts {
    /// For one commit message from a diff.
    public static func message(style: CommitStyle, adding addition: AIInstructionAddition?) -> String {
        let lines = [
            "You write git commit messages for a developer's staged changes. Describe what the change does and why, based only on the diff. Never invent details.",
            subjectRule(style),
        ]
        return AIInstructionAddition.applying(addition, to: (lines + examples(style)).joined(separator: "\n\n"))
    }

    /// For splitting changes into commits, each with a message. `messages` are the user's
    /// instructions for commit messages; `grouping`, for how changes are split.
    public static func plan(
        style: CommitStyle, messages: AIInstructionAddition?, grouping: AIInstructionAddition?
    ) -> String {
        let lines = [
            "You split a developer's uncommitted changes into a few logical commits, the way a careful engineer would: one coherent change per commit, with tests next to the code they test. Base everything on the diff; never invent details. Every file goes in exactly one commit.",
            subjectRule(style),
        ]
        let builtIn = (lines + examples(style)).joined(separator: "\n\n")
        let withMessages = AIInstructionAddition.applying(messages, to: builtIn, about: "commit messages")
        return AIInstructionAddition.applying(grouping, to: withMessages, about: "how to split the changes")
    }

    private static func subjectRule(_ style: CommitStyle) -> String {
        guard style.isConventional else {
            return "Subjects match the repository's own style: a short sentence-case summary, no type prefix."
        }
        var convention =
            "Subjects use Conventional Commits: \"type(scope): summary\" with type one of feat, fix, refactor, docs, test, chore, perf, style, build, ci."
        if !style.commonScopes.isEmpty {
            convention += " Scopes this repository uses: \(style.commonScopes.joined(separator: ", "))."
        }
        return convention
    }

    private static func examples(_ style: CommitStyle) -> [String] {
        guard !style.examples.isEmpty else { return [] }
        return [
            "Recent subjects in this repository. Match their style only; describe the diff, not these:\n"
                + style.examples.map { "- \($0)" }.joined(separator: "\n")
        ]
    }
}
