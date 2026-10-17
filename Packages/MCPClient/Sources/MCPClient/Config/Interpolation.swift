import Foundation

/// The `${…}` variables agents expand in their MCP configuration.
enum Interpolation {
    static func expand(_ text: String, style: ValueResolution, environment: [String: String], project: URL?) -> String {
        guard text.contains("${") else { return text }
        var result = ""
        var rest = Substring(text)
        while let start = rest.range(of: "${") {
            result += rest[..<start.lowerBound]
            guard let end = rest[start.upperBound...].firstIndex(of: "}") else {
                result += rest[start.lowerBound...]
                return result
            }
            let expression = String(rest[start.upperBound..<end])
            result += value(of: expression, style: style, environment: environment, project: project) ?? "${\(expression)}"
            rest = rest[rest.index(after: end)...]
        }
        return result + rest
    }

    /// Unknown variables stay as written, so the launch fails visibly instead of with a blank.
    private static func value(of expression: String, style: ValueResolution, environment: [String: String], project: URL?) -> String? {
        switch style {
        case .claudeCode:
            // `${VAR:-default}` falls back when VAR is unset or empty.
            if let separator = expression.range(of: ":-") {
                let name = String(expression[..<separator.lowerBound])
                let fallback = String(expression[separator.upperBound...])
                return environment[name].flatMap { $0.isEmpty ? nil : $0 } ?? fallback
            }
            return environment[expression]
        case .cursor:
            if expression.hasPrefix("env:") {
                return environment[String(expression.dropFirst(4))]
            }
            switch expression {
            case "userHome": return environment["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
            case "workspaceFolder": return project.map(ProjectPath.key)
            case "workspaceFolderBasename": return project?.lastPathComponent
            case "pathSeparator", "/": return "/"
            default: return nil
            }
        case .none, .codex:
            return nil
        }
    }
}
