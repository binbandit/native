import AIInstructions
import Foundation

// Tasks side by side in a project's sidebar have to be told apart. A new task whose title matches
// another live task's in the same project is named for what's specific in its own message, or else
// as a repeat; numbers only when nothing else is left.
extension SessionTitleRules {
    /// The project `folder` belongs to: the main checkout when it's a linked worktree (tasks get one
    /// of their own outside the project), else the folder itself.
    public static func projectFolder(of folder: URL) -> URL {
        AIInstructionProject.mainCheckout(ofWorktree: folder) ?? folder
    }

    /// The project `folder` belongs to, as a path to compare: two tasks are in the same project
    /// when theirs match.
    public static func projectKey(of folder: URL) -> String {
        AIInstructionProject.key(for: projectFolder(of: folder))
    }

    /// `title`, told apart from `others` (the titles of the project's other live tasks) when it
    /// matches one: by a detail from the task's own message (a file, a command, a name), else as
    /// "again", else numbered.
    public static func distinct(_ title: String, from others: [String], prompt: String) -> String {
        let taken = Set(others.map { $0.lowercased() })
        guard taken.contains(title.lowercased()) else { return title }
        let candidates =
            details(in: prompt).filter { !title.localizedCaseInsensitiveContains($0) }.map { "\(title) (\($0))" }
            + ["\(title) again"]
        if let free = candidates.first(where: { !taken.contains($0.lowercased()) }) {
            return free
        }
        let repeats = others.filter { $0.lowercased().hasPrefix(title.lowercased()) }.count
        return ((repeats + 1)...).lazy.map { "\(title) (\($0))" }.first { !taken.contains($0.lowercased()) } ?? title
    }

    /// The longest a detail may be and still read as part of a title.
    static let detailLimit = 40

    /// What a message names specifically, in the order it names them: code in backticks, quoted
    /// text, and file names, paths, flags and identifiers.
    static func details(in prompt: String) -> [String] {
        var details: [String] = []
        for match in prompt.matches(of: #/`[^`\n]+`|"[^"\n]+"/#) {
            details.append(String(match.output))
        }
        for word in prompt.split(whereSeparator: \.isWhitespace) {
            let word = word.trimmingCharacters(
                in: .punctuationCharacters.subtracting(CharacterSet(charactersIn: "-_/."))
            ).trimmingCharacters(in: CharacterSet(charactersIn: ".,:;"))
            guard !word.hasPrefix("`"), !word.hasPrefix("\""), isSpecific(word) else { continue }
            details.append(word)
        }
        var seen: Set<String> = []
        return details.filter {
            $0.count <= detailLimit && SessionTitleInput.isSafeTitle($0)
                && seen.insert($0.lowercased()).inserted
        }
    }

    /// A word that names one thing: a file (`greet.py`), a path, a flag (`--shout`), or an
    /// identifier (`snake_case`, `camelCase`).
    private static func isSpecific(_ word: String) -> Bool {
        guard word.count > 1, word.contains(where: \.isLetter) else { return false }
        if word.hasPrefix("--") || word.contains("/") || word.contains("_") { return true }
        if word.wholeMatch(of: #/[A-Za-z0-9-]+\.[A-Za-z0-9]{1,8}/#) != nil { return true }
        return word.dropFirst().contains(where: \.isUppercase) && word.contains(where: \.isLowercase)
            && word.allSatisfy { $0.isLetter || $0.isNumber }
    }
}
