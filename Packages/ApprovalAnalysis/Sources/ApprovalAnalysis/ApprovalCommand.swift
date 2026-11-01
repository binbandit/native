import Foundation

/// A conservative description, never an authorization or a shell interpreter. All tool-specific
/// claims come from reviewed data. Lexical paths are not observations of files or symbolic links.
public struct ApprovalCommand: Equatable, Sendable {
    /// Only `irreversible` asks for a deliberate hold. Running project code, building and pushing
    /// new commits are routine; unknown commands make no claims either way.
    public enum Risk: Equatable, Sendable { case routine, irreversible, unknown }

    public struct Part: Equatable, Sendable, Identifiable {
        public let range: Range<Int>
        public let explanation: String
        /// The part that makes the command irreversible, marked so it stands out from the rest.
        public let destructive: Bool
        public var id: Int { range.lowerBound }
    }

    public let command: String
    public let risk: Risk
    public let action: String
    /// What happens, in a sentence or two, for a known command; for an unknown one, that Native
    /// makes no claims, and where it runs.
    public let consequence: String
    public private(set) var parts: [Part]
    public let suggestedCommand: String?
    public let suggestedExplanation: String?
    /// Only a literal, unrecognized executable name. No arguments, paths, or shell fragments.
    public let unknownProgram: String?
    /// Where a `git push` sends commits, when its arguments say so plainly.
    public let pushTarget: GitPushTarget?

    /// What the agent wants to do, as the ask's headline says it: the consequence for a push
    /// ("overwrite main on origin"), otherwise the command's action.
    public var headline: String { pushTarget?.headline(place: nil) ?? action }

    public init(
        command: String, workingDirectory: String, worktreeDirectory: String? = nil, homeDirectory: String? = nil,
        knowledge: CommandKnowledge = .bundled
    ) {
        self.command = command
        let root = worktreeDirectory ?? workingDirectory
        let startsInside = CommandKnowledgeMatch.isInside(workingDirectory, root: root)
        let folderName = URL(filePath: workingDirectory).standardizedFileURL.lastPathComponent
        let words = ApprovalCommandWords(command)
        let executable = words?.tokens.first?.value
        unknownProgram = executable.flatMap {
            !knowledge.recognizes($0) && CommandKnowledgeValidation.identifier($0) && $0.count <= 64
                && !$0.hasPrefix("-") && !$0.hasPrefix(".") ? $0 : nil
        }
        guard let words,
            let match = CommandKnowledgeMatch(words: words, knowledge: knowledge)
        else {
            let name = executable.map { URL(filePath: $0).lastPathComponent }
            risk = .unknown
            action = name.map { "run \($0)" } ?? "run this command"
            consequence =
                "Native can't describe \(name ?? "this command"), so it makes no claims about it. "
                + "It runs in \(folderName)\(startsInside ? "" : ", outside the worktree"), with your permissions."
            parts = []
            suggestedCommand = nil
            suggestedExplanation = nil
            pushTarget = nil
            return
        }
        let rule = match.rule
        let raisingOperands = match.operands.filter { operand in
            (rule.destructiveOperandPrefixes ?? []).contains { operand.value.hasPrefix($0) }
        }
        let raised = match.options.contains(where: { $0.option.destructive }) || !raisingOperands.isEmpty
        risk = rule.destructive || raised ? .irreversible : .routine
        action = rule.summary.replacingOccurrences(of: "{count}", with: String(match.operands.count))
        let sentence = (!rule.destructive && raised ? rule.destructiveConsequence : nil) ?? rule.consequence
        consequence = sentence.replacingOccurrences(of: "{folder}", with: startsInside ? "the worktree" : folderName)
        let target = GitPushTarget(match: match)
        pushTarget = target
        var annotations = [Part(range: match.prefix, explanation: action, destructive: rule.destructive)]
        annotations += match.options.map {
            .init(range: $0.range, explanation: $0.option.summary, destructive: $0.option.destructive)
        }
        if let terminator = match.terminator {
            annotations.append(
                .init(range: terminator, explanation: "what follows are names, not options", destructive: false))
        }
        if let target, let range = target.range {
            annotations.append(
                .init(range: range, explanation: target.description, destructive: !raisingOperands.isEmpty))
        } else if let template = rule.operands.summary {
            annotations += match.operands.map { operand in
                var text = template
                if rule.operands.paths {
                    let facts = CommandKnowledgeMatch.pathFacts(
                        operand, cwd: workingDirectory, root: root, home: homeDirectory, knowledge: knowledge)
                    text = text.replacingOccurrences(of: "{scope}", with: facts.scope)
                        .replacingOccurrences(of: "{location}", with: facts.location ?? "{value}")
                }
                // Substitute user text last, so its braces can never become template instructions.
                text = text.replacingOccurrences(of: "{value}", with: operand.value)
                return Part(range: operand.range, explanation: text, destructive: false)
            }
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

    /// The same description with the push target's annotation replaced, once the host has read what
    /// the remote is and what it holds.
    public func describingPushTarget(_ explanation: String) -> Self {
        guard let range = pushTarget?.range, let index = parts.firstIndex(where: { $0.range == range }) else {
            return self
        }
        var copy = self
        copy.parts[index] = Part(range: range, explanation: explanation, destructive: parts[index].destructive)
        return copy
    }
}
