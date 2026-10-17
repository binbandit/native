import Foundation

/// What a script run produced. A failed script still has the output and tool calls it made first.
public struct ScriptRunResult: Sendable, Hashable {
    /// One entry per `text()` or `console.log()` call, in order.
    public var output: [String]
    public var toolCalls: [ScriptToolCall]
    /// Nil when the script finished (including through `exit()`).
    public var failure: ScriptFailure?
    public var duration: Duration

    public init(output: [String], toolCalls: [ScriptToolCall], failure: ScriptFailure?, duration: Duration) {
        self.output = output
        self.toolCalls = toolCalls
        self.failure = failure
        self.duration = duration
    }

    public var succeeded: Bool { failure == nil }

    /// The output as one text, a line per `text()` call.
    public var text: String { output.joined(separator: "\n") }

    /// The result as a model should read it: the script's output, then what went wrong, if anything.
    public var report: String {
        var parts: [String] = []
        if !output.isEmpty {
            parts.append(text)
        }
        if let failure {
            parts.append(failure.report)
        } else if output.isEmpty {
            parts.append("The script finished without output. Call text() to return what you need.")
        }
        return parts.joined(separator: "\n\n")
    }

    /// The result as structured content: `{ output, tool_calls, failure? }`.
    public var summary: ScriptJSON {
        var object: [String: ScriptJSON] = [
            "output": .string(text),
            "tool_calls": .number(Double(toolCalls.count)),
        ]
        if let failure {
            var detail: [String: ScriptJSON] = [
                "kind": .string(failure.kind.rawValue), "message": .string(failure.message),
            ]
            detail["line"] = failure.line.map { .number(Double($0)) }
            detail["column"] = failure.column.map { .number(Double($0)) }
            object["failure"] = .object(detail)
        }
        return .object(object)
    }
}

/// One call a script made to a bound tool.
public struct ScriptToolCall: Sendable, Hashable {
    public var path: [String]
    public var input: ScriptJSON
    public var isError: Bool
    public var duration: Duration

    public init(path: [String], input: ScriptJSON, isError: Bool, duration: Duration) {
        self.path = path
        self.input = input
        self.isError = isError
        self.duration = duration
    }
}

/// Why a script didn't finish, with where in the script when that's known.
public struct ScriptFailure: Error, Sendable, Hashable, Decodable, LocalizedError {
    public enum Kind: String, Sendable, Hashable, Decodable {
        /// The script doesn't parse, or imports a module.
        case syntax
        /// It threw, or a promise it awaited rejected (such as a failed tool call).
        case exception
        /// It used more memory than its heap limit.
        case memory
        /// It emitted more text than it may.
        case outputLimit = "output_limit"
        /// It awaits something nothing will settle.
        case stalled
        /// It ran past its time limit and was stopped.
        case timedOut = "timed_out"
        /// It made more tool calls than it may.
        case toolCallLimit = "tool_call_limit"
        /// The runtime crashed, broke the protocol, or failed internally.
        case runtime
        /// A kind this version doesn't know, from a newer runtime.
        case unknown

        public init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            // The runtime calls its own failures "internal".
            self = raw == "internal" ? .runtime : Kind(rawValue: raw) ?? .unknown
        }
    }

    public var kind: Kind
    public var message: String
    /// 1-based, in the script as written.
    public var line: Int?
    public var column: Int?

    public init(kind: Kind, message: String, line: Int? = nil, column: Int? = nil) {
        self.kind = kind
        self.message = message
        self.line = line
        self.column = column
    }

    public var errorDescription: String? { report }

    /// "Script failed at line 3, column 9: TypeError: …"
    public var report: String {
        let place = line.map { line in " at line \(line)" + (column.map { ", column \($0)" } ?? "") } ?? ""
        let what: String =
            switch kind {
            case .syntax: "Script didn't compile"
            case .timedOut: "Script was stopped"
            case .runtime: "Script runtime failed"
            default: "Script failed"
            }
        return "\(what)\(place): \(message)"
    }
}
