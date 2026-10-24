import Foundation

/// A conservative description, never an authorization or a shell interpreter. All tool-specific
/// claims come from reviewed data. Lexical paths are not observations of files or symbolic links.
public struct ApprovalCommand: Equatable, Sendable {
    public enum Risk: Equatable, Sendable { case routine, irreversible, unknown }

    public struct Part: Equatable, Sendable, Identifiable {
        public let range: Range<Int>
        public let explanation: String
        public let destructive: Bool
        public var id: Int { range.lowerBound }
    }

    public let command: String
    public let risk: Risk
    public let action: String
    public let reason: String
    public let consequence: String
    public let parts: [Part]
    public let suggestedCommand: String?
    public let suggestedExplanation: String?
    /// Only a literal, unrecognized executable name. No arguments, paths, or shell fragments.
    public let unknownProgram: String?

    public init(
        command: String, workingDirectory: String, worktreeDirectory: String? = nil, homeDirectory: String? = nil,
        knowledge: CommandKnowledge = .bundled
    ) {
        self.command = command
        let root = worktreeDirectory ?? workingDirectory
        let startsInside = CommandKnowledgeMatch.isInside(workingDirectory, root: root)
        let words = ApprovalCommandWords(command)
        let executable = words?.tokens.first?.value
        let name = executable.map { URL(filePath: $0).lastPathComponent }
        unknownProgram = executable.flatMap {
            !knowledge.recognizes($0) && CommandKnowledgeValidation.identifier($0) && $0.count <= 64
                && !$0.hasPrefix("-") && !$0.hasPrefix(".") ? $0 : nil
        }
        guard let words,
            let match = CommandKnowledgeMatch(words: words, knowledge: knowledge)
        else {
            risk = .unknown
            action = name.map { "run \($0)" } ?? "run this command"
            reason =
                startsInside
                ? "Requested from this task's worktree." : "Requested from a folder outside the worktree."
            consequence =
                "Native can't describe this command, so it makes no claims about its effects or whether they can be undone."
            parts = []
            suggestedCommand = nil
            suggestedExplanation = nil
            return
        }
        let rule = match.rule
        risk = rule.destructive || match.options.contains(where: { $0.option.destructive }) ? .irreversible : .routine
        action = rule.summary.replacingOccurrences(of: "{count}", with: String(match.operands.count))
        reason =
            startsInside
            ? "Requested from this task's worktree. Effects are described from known command syntax."
            : "Requested from outside the worktree. Effects are described from known command syntax."
        consequence = rule.consequence
        var annotations = [Part(range: match.prefix, explanation: action, destructive: rule.destructive)]
        annotations += match.options.map {
            .init(range: $0.range, explanation: $0.option.summary, destructive: $0.option.destructive)
        }
        if let terminator = match.terminator {
            annotations.append(
                .init(range: terminator, explanation: "the remaining arguments are operands", destructive: false))
        }
        annotations += match.operands.map { operand in
            var text = rule.operands.summary
            if rule.operands.paths {
                let facts = CommandKnowledgeMatch.pathFacts(
                    operand, cwd: workingDirectory, root: root, home: homeDirectory, knowledge: knowledge)
                text = text.replacingOccurrences(of: "{scope}", with: facts.scope)
                    .replacingOccurrences(of: "{location}", with: facts.location)
            } else {
                text = text.replacingOccurrences(of: "{scope}", with: "location not inspected")
                    .replacingOccurrences(of: "{location}", with: "operand")
            }
            // Substitute user text last, so its braces can never become template instructions.
            text = text.replacingOccurrences(of: "{value}", with: operand.value)
            return Part(range: operand.range, explanation: text, destructive: rule.destructive)
        }
        parts = annotations.sorted { $0.range.lowerBound < $1.range.lowerBound }
        let replacements = match.options.filter { $0.option.replacement != nil }
        let blockedOption = match.options.contains { matched in
            (rule.noSuggestionWithOptions ?? []).contains { matched.option.names.contains($0) }
        }
        let blockedOperand = match.operands.contains { operand in
            (rule.noSuggestionWithOperandPrefixes ?? []).contains { operand.value.hasPrefix($0) }
        }
        if !replacements.isEmpty && !blockedOption && !blockedOperand {
            var characters = Array(command)
            for replacement in replacements.reversed() {
                if let value = replacement.option.replacement {
                    characters.replaceSubrange(replacement.range, with: Array(value))
                }
            }
            suggestedCommand = String(characters)
            suggestedExplanation = replacements.first?.option.alternative
        } else {
            suggestedCommand = nil
            suggestedExplanation = nil
        }
    }
}
