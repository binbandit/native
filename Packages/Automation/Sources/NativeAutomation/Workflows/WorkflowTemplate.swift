import Foundation

/// The `{{variable}}` syntax of step prompts. Deliberately tiny: values in, text out, no logic, so a
/// definition reads the same as the prompt the agent gets.
///
/// Variables: `{{input}}` (what the user typed), `{{title}}` (the run's title), `{{cwd}}`,
/// `{{project}}` (the folder's name), `{{steps.<id>.output}}` (a finished step's result) and
/// `{{steps.<id>.agent}}` (the agent it ran on).
public nonisolated enum WorkflowTemplate {
    public enum Variable: Hashable, Sendable {
        case input, title, cwd, project
        case stepOutput(String)
        case stepAgent(String)
        case unknown(String)

        public init(_ name: String) {
            let parts = name.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            switch (parts.count, parts.first, parts.last) {
            case (1, "input", _): self = .input
            case (1, "title", _): self = .title
            case (1, "cwd", _): self = .cwd
            case (1, "project", _): self = .project
            case (3, "steps", "output"): self = .stepOutput(parts[1])
            case (3, "steps", "agent"): self = .stepAgent(parts[1])
            default: self = .unknown(name)
            }
        }

        public var referencedStep: String? {
            switch self {
            case .stepOutput(let step), .stepAgent(let step): step
            default: nil
            }
        }
    }

    /// The values a run has to fill a template with.
    public struct Values: Sendable {
        public var input: String
        public var title: String
        public var cwd: URL
        /// Finished steps' outputs by step id; a skipped step has none.
        public var outputs: [String: String] = [:]
        public var agents: [String: String] = [:]

        public func value(of variable: Variable) -> String {
            switch variable {
            case .input: input
            case .title: title
            case .cwd: cwd.path(percentEncoded: false)
            case .project: cwd.lastPathComponent
            // Say so rather than leave a hole, so the agent isn't left guessing at an empty section.
            case .stepOutput(let step): outputs[step].flatMap { $0.isEmpty ? nil : $0 } ?? "(No output: that step was skipped or didn't reply.)"
            case .stepAgent(let step): agents[step] ?? "another agent"
            case .unknown(let name): "{{\(name)}}"
            }
        }
    }

    public static func render(_ template: String, with values: Values) -> String {
        var result = ""
        var rest = Substring(template)
        while let open = rest.range(of: "{{") {
            guard let close = rest[open.upperBound...].range(of: "}}") else { break }
            result += rest[..<open.lowerBound]
            let name = rest[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespaces)
            result += values.value(of: Variable(name))
            rest = rest[close.upperBound...]
        }
        result += rest
        return result
    }

    public static func variables(in template: String) -> [Variable] {
        var found: [Variable] = []
        var rest = Substring(template)
        while let open = rest.range(of: "{{"), let close = rest[open.upperBound...].range(of: "}}") {
            found.append(Variable(rest[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespaces)))
            rest = rest[close.upperBound...]
        }
        return found
    }
}
