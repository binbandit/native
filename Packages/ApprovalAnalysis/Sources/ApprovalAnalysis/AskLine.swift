import ACP
import Foundation

/// One sentence for navigation. It describes a request, never authorizes it; full commands and
/// failure details stay in the task. Rendering and truncation belong to the client.
public struct AskLine: Equatable, Sendable {
    public let text: String

    public init(
        permission: RequestPermissionRequest, workingDirectory: String,
        pushPlace: String? = nil, pushBranch: String? = nil, knowledge: CommandKnowledge = .bundled
    ) {
        var state = SessionState()
        state.apply(.toolCall(permission.toolCall))
        guard case .toolCall(let call)? = state.items.first else {
            self.init(question: "Review this request?")
            return
        }
        self.init(
            call: call, workingDirectory: workingDirectory, pushPlace: pushPlace,
            pushBranch: pushBranch, knowledge: knowledge)
    }

    /// A folded call retains fields a permission request may omit.
    public init(
        call: ToolCallState, workingDirectory: String,
        pushPlace: String? = nil, pushBranch: String? = nil, knowledge: CommandKnowledge = .bundled
    ) {
        if call.name == "AskUserQuestion" {
            if case .array(let questions) = call.rawInput?["questions"],
                let question = questions.first?["question"]?.stringValue
            {
                text = Self(question: question).text
            } else {
                text = Self(question: "Answer the agent's question?").text
            }
        } else if call.kind == .switchMode || call.name == "ExitPlanMode" {
            text = Self(planStepCount: nil).text
        } else if let mcp = call.mcpTool {
            text = "Use \(Self.code(mcp.tool)) from \(Self.code(mcp.server))?"
        } else if let command = call.shellCommand {
            text = Self.command(
                command, workingDirectory: call.rawInput?["cwd"]?.stringValue ?? workingDirectory,
                worktreeDirectory: workingDirectory, pushPlace: pushPlace, pushBranch: pushBranch,
                knowledge: knowledge)
        } else {
            let wording = call.wording
            if wording.verb == .fetch {
                text = "Open \(Self.line(wording.object))?"
                return
            }
            switch call.kind {
            case .edit:
                let count = max(
                    ToolWorkSummary(calls: [call]).counts[.edit] ?? 1,
                    Set(call.locations.map(\.path)).count)
                text = count > 1 ? "Edit \(count) files?" : "Edit \(Self.object(wording))?"
            case .delete:
                let count = Set(call.locations.map(\.path)).count
                text = count > 1 ? "Delete \(count) files?" : "Delete \(Self.object(wording))?"
            case .fetch:
                text = "Open a web page?"
            case .execute:
                text = "Run this command?"
            case .read, .search, .move:
                if let verb = wording.verb {
                    text = "\(verb.form(for: .awaitingApproval)) \(Self.object(wording))?"
                } else {
                    text = "Review this request?"
                }
            case .think, .switchMode:
                text = "Review the plan?"
            case .other:
                text = "Review this request?"
            }
        }
    }

    public init(question: String) {
        let question = Self.line(question)
        text = question.isEmpty ? "Answer the agent's question?" : question
    }

    /// Count structured steps supplied by the agent, never infer steps from its Markdown.
    public init(planStepCount: Int?) {
        if let count = planStepCount, count > 0 {
            text = "Plan ready: \(count) \(count == 1 ? "step" : "steps")"
        } else {
            text = "Plan ready"
        }
    }

    /// The host supplies the known cause; this formatter never guesses from tool output or names.
    public enum Failure: Equatable, Sendable {
        case overloaded(model: String)
        case signIn(agent: String)
        case pushBranchMoved(branch: String)
        case other(message: String)
    }

    /// A recovered failure belongs in the transcript, with no failure line in navigation.
    public init?(failure: Failure, recovered: Bool = false) {
        guard !recovered else { return nil }
        switch failure {
        case .overloaded(let model): text = "\(Self.line(model)) was overloaded"
        case .signIn(let agent): text = "\(Self.line(agent)) needs you to sign in"
        case .pushBranchMoved(let branch): text = "Couldn't push: \(Self.code(branch)) moved"
        case .other(let message):
            let firstLine = message.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            let message = Self.line(firstLine)
            text = message.isEmpty ? "The task stopped unexpectedly" : message
        }
    }

    private static func command(
        _ command: String, workingDirectory: String, worktreeDirectory: String,
        pushPlace: String?, pushBranch: String?, knowledge: CommandKnowledge
    ) -> String {
        // Use the same conservative lexer and reviewed grammar as the permission card. An
        // unsupported suffix must never be hidden behind a familiar-looking command prefix.
        guard let words = ApprovalCommandWords(command), let executable = words.tokens.first else {
            return "Run this command?"
        }
        let match = CommandKnowledgeMatch(words: words, knowledge: knowledge)
        let analysis = ApprovalCommand(
            command: command, workingDirectory: workingDirectory, worktreeDirectory: worktreeDirectory,
            knowledge: knowledge)
        if analysis.risk == .irreversible {
            let phrase: String
            if let target = analysis.pushTarget {
                phrase = target.headline(place: pushPlace, destination: pushBranch, marking: code)
            } else if let match, match.executables.contains("rm"), match.operands.count == 1,
                let path = match.operands.first?.value
            {
                phrase = "delete \(code(path))"
            } else if let match, match.executables.contains("rm") {
                phrase = "delete \(match.operands.count) files or folders"
            } else if let option = match?.options.first(where: { $0.option.destructive }),
                match?.rule.destructive == false
            {
                phrase = option.option.summary
            } else {
                phrase = analysis.action
            }
            return line(phrase.prefix(1).uppercased() + phrase.dropFirst()) + "?"
        }
        guard match != nil || !knowledge.recognizes(executable.value) else { return "Run this command?" }
        let binary = URL(filePath: executable.value).lastPathComponent
        let short = ([binary] + (match?.rule.words ?? [])).joined(separator: " ")
        return "Run \(code(short))?"
    }

    private static func object(_ wording: ToolCallWording) -> String {
        wording.objectIsCode ? code(wording.object) : line(wording.object)
    }

    private static func line(_ value: String) -> String {
        value.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }

    private static func code(_ value: String) -> String {
        let value = line(value)
        var delimiter = "`"
        while value.contains(delimiter) { delimiter += "`" }
        let padding = value.hasPrefix("`") || value.hasSuffix("`") ? " " : ""
        return delimiter + padding + value + padding + delimiter
    }
}
