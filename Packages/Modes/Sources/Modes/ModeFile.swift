import Foundation

/// A mode as a Markdown file: frontmatter for its settings, the body as its instructions. Projects
/// share modes this way, committed as `.native/modes/<name>.md`:
///
///     ---
///     name: Security Review
///     symbol: lock.shield
///     description: Looks for security problems in the current changes
///     autonomy: read-only
///     ---
///     Review the current changes for security problems…
///
/// Every key is optional: `name` defaults to the file's name, `symbol` to a generic one, and
/// `description` to the instructions' first line. `autonomy` is one of `ModeAutonomy`'s values;
/// `plan: true` uses the agent's plan mode; `model` and `effort` name the agent's own values.
public enum ModeFile {
    /// The folder in a project that holds its modes.
    public static let folder = ".native/modes"
    public static let fileExtension = "md"
    /// Larger files are refused: instructions go to the agent with a prompt.
    public static let maximumSize = 32 * 1024
    public static let defaultSymbol = "wand.and.stars"

    /// A file that couldn't be used as a mode, and why, in words for Settings.
    public struct Problem: Hashable, Sendable, Error {
        public var file: String
        public var reason: String
    }

    /// What reading one file gave: a mode, with anything in it that was ignored.
    public struct Parsed: Hashable, Sendable {
        public var mode: Mode
        public var warnings: [String]
    }

    /// Reads `text`, the contents of the file named `fileName` ("security-review.md").
    /// `source` decides the id, and limits a project's modes to settings that can only make the
    /// agent more careful (`ModeAutonomy.isAllowedInProjects`).
    public static func parse(_ text: String, fileName: String, source: Mode.Source = .project) -> Result<
        Parsed, Problem
    > {
        let slug = slug(for: fileName)
        func problem(_ reason: String) -> Result<Parsed, Problem> {
            .failure(Problem(file: fileName, reason: reason))
        }
        guard text.utf8.count <= maximumSize else {
            return problem("It's over \(maximumSize / 1024) KB. Keep a mode's instructions shorter than that.")
        }
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var fields: [String: (value: String, line: Int)] = [:]
        var warnings: [String] = []
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---" {
            guard let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" })
            else {
                return problem("The settings at the top never end: add a line with just --- after them.")
            }
            for index in 1..<end {
                let line = lines[index].trimmingCharacters(in: .whitespaces)
                guard !line.isEmpty, !line.hasPrefix("#") else { continue }
                guard let colon = line.firstIndex(of: ":") else {
                    return problem("Line \(index + 1) isn't a setting like name: Review.")
                }
                let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                fields[key] = (unquoted(line[line.index(after: colon)...]), index + 1)
            }
            lines.removeSubrange(0...end)
        }
        let instructions = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instructions.isEmpty else {
            return problem("There are no instructions: write what the agent should do below the settings.")
        }
        var settings = ModeSettings()
        for (key, field) in fields.sorted(by: { $0.value.line < $1.value.line }) {
            let value = field.value
            switch key {
            case "name", "symbol", "description":
                continue
            case "autonomy":
                guard let autonomy = ModeAutonomy(rawValue: value.lowercased()) else {
                    let allowed = ModeAutonomy.allCases.map(\.rawValue).joined(separator: ", ")
                    return problem("autonomy: \(value) isn't one of \(allowed).")
                }
                if source == .project, !autonomy.isAllowedInProjects {
                    warnings.append(
                        "autonomy: \(value) is ignored. A project's mode can make the agent more careful, never give it more freedom, so the task keeps its own level."
                    )
                } else {
                    settings.autonomy = autonomy
                }
            case "plan":
                guard let plan = Bool(value.lowercased()) else {
                    return problem("plan: \(value) should be true or false.")
                }
                settings.usesPlanMode = plan
            case "model":
                settings.model = value.isEmpty ? nil : value
            case "effort":
                settings.effort = value.isEmpty ? nil : value
            default:
                warnings.append("\(key) on line \(field.line) isn't a mode setting, so it's ignored.")
            }
        }
        let name = fields["name"]?.value.nilIfEmpty ?? title(for: slug)
        guard !name.isEmpty else { return problem("The mode needs a name.") }
        let summary = fields["description"]?.value.nilIfEmpty ?? firstLine(of: instructions)
        let id: Mode.ID = source == .project ? .project(slug) : .custom(slug)
        let mode = Mode(
            id: id, name: name, symbol: fields["symbol"]?.value.nilIfEmpty ?? defaultSymbol, summary: summary,
            instructions: instructions, settings: settings, source: source)
        return .success(Parsed(mode: mode, warnings: warnings))
    }

    /// The file for `mode`, which `parse` reads back to the same mode: for sharing one of the
    /// user's own modes with a project.
    public static func contents(of mode: Mode) -> String {
        var lines = ["---", "name: \(mode.name)", "symbol: \(mode.symbol)", "description: \(mode.summary)"]
        if let autonomy = mode.settings.autonomy { lines.append("autonomy: \(autonomy.rawValue)") }
        if mode.settings.usesPlanMode { lines.append("plan: true") }
        if let model = mode.settings.model { lines.append("model: \(model)") }
        if let effort = mode.settings.effort { lines.append("effort: \(effort)") }
        lines.append("---")
        return lines.joined(separator: "\n") + "\n" + mode.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
            + "\n"
    }

    /// The file name for a mode called `name`: "Security Review" → "security-review.md".
    public static func fileName(for name: String) -> String {
        let words = name.lowercased().split { !$0.isLetter && !$0.isNumber }
        return (words.isEmpty ? "mode" : words.joined(separator: "-")) + "." + fileExtension
    }

    static func slug(for fileName: String) -> String {
        let base = fileName.hasSuffix(".\(fileExtension)") ? String(fileName.dropLast(fileExtension.count + 1)) : fileName
        return base.lowercased()
    }

    private static func title(for slug: String) -> String {
        slug.split { $0 == "-" || $0 == "_" || $0 == " " }.map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private static func firstLine(of text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        let plain = line.trimmingCharacters(in: CharacterSet(charactersIn: "#-* ").union(.whitespaces))
        return plain.count > 90 ? String(plain.prefix(89)) + "…" : plain
    }

    private static func unquoted(_ value: Substring) -> String {
        let value = value.trimmingCharacters(in: .whitespaces)
        for quote in ["\"", "'"] where value.count >= 2 && value.hasPrefix(quote) && value.hasSuffix(quote) {
            return String(value.dropFirst().dropLast())
        }
        return value
    }
}

extension String {
    fileprivate var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
