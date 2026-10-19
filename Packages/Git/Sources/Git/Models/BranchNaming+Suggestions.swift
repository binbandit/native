import AIInstructions
import Foundation

/// Branch names the on-device model suggests, for users who gave instructions for them ("prefix
/// with brayden/", "start with the Jira key"). Without instructions a branch is named from the
/// task's title alone (`name(forTitle:prefix:)`), which needs no model.
extension BranchNaming {
    /// The longest name a suggestion keeps.
    static let suggestionLimit = 80

    /// What the model is told. `prefix` is the one the user's settings give new branches.
    public static func suggestionInstructions(prefix: String, adding addition: AIInstructionAddition?) -> String {
        let example = prefix + "fix-login-redirect"
        let start = prefix.isEmpty ? "" : "start with \(prefix), then "
        let builtIn = """
            You name the git branch for a task in a coding agent app, from the task's title and the user's request. \
            Answer with the branch name only.
            Required: only ASCII letters, digits, hyphens, and slashes between parts. No spaces. At most \
            \(suggestionLimit) characters.
            By default, \(start)use 2 to 5 lowercase words joined by hyphens that say what the task changes, \
            like \(example). The user's instructions may change the prefix, the words or their case. Copy any \
            ticket key or name from the request exactly as written.
            """
        return AIInstructionAddition.applying(addition, to: builtIn)
    }

    /// The task, as the model sees it.
    public static func suggestionPrompt(title: String, request: String?) -> String {
        var prompt = "Task title: \(title)"
        if let request = request?.trimmingCharacters(in: .whitespacesAndNewlines), !request.isEmpty {
            prompt += "\nUser's request:\n\(request.prefix(1_500))"
        }
        return prompt
    }

    /// A branch name from what the model answered: its first line, with anything git wouldn't
    /// take replaced by hyphens, each `/` part tidied, and capped. Case is kept, so ticket keys
    /// like `ABC-123` survive. Nil when nothing usable is left.
    public static func name(fromSuggestion suggestion: String) -> String? {
        var line = suggestion.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        line = line.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\"'`")))
        if line.hasPrefix("refs/heads/") { line = String(line.dropFirst("refs/heads/".count)) }
        let segments = line.split(separator: "/").compactMap(cleanSegment)
        guard !segments.isEmpty else { return nil }
        var name = segments.joined(separator: "/")
        if name.count > suggestionLimit {
            name = String(name.prefix(suggestionLimit))
            while let last = name.last, "-./_".contains(last) { name.removeLast() }
        }
        return name.isEmpty ? nil : name
    }

    /// One part of a branch name, with only characters every git ref allows, or nil when empty.
    private static func cleanSegment(_ segment: Substring) -> String? {
        var cleaned = ""
        for scalar in segment.unicodeScalars {
            let allowed = scalar.isASCII && (scalar.properties.isAlphabetic || ("0"..."9").contains(scalar))
            if allowed || "-_.".unicodeScalars.contains(scalar) {
                cleaned.unicodeScalars.append(scalar)
            } else if !cleaned.hasSuffix("-") {
                cleaned.append("-")
            }
        }
        cleaned = cleaned.replacing(/-{2,}/, with: "-").replacing(/\.{2,}/, with: ".")
        while cleaned.hasSuffix(".lock") { cleaned.removeLast(".lock".count) }
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "-._"))
        return cleaned.isEmpty ? nil : cleaned
    }
}
