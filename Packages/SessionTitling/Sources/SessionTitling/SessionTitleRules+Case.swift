import Foundation

// One style for every title Native writes or shows from a model, whichever wrote it (the on-device
// model, a client's titler, the agent): sentence case, like a commit subject. Models sometimes
// answer in Title Case ("Run Tests and Fix Failures"); that's turned into "Run tests and fix
// failures" without touching what has to keep its case. The user's own titles are never changed.
extension SessionTitleRules {
    /// `title` in sentence case: its first word capitalized and, when the title is in Title Case,
    /// its other plainly capitalized words lowercased. Acronyms ("README", "API"), mixed-case names
    /// ("SwiftUI", "iOS"), code and file names ("`kt`", "main.swift"), well-known names, and words
    /// `source` (the task's first message) capitalizes mid-sentence ("Linux") keep their case.
    public static func sentenceCase(_ title: String, keeping source: String? = nil) -> String {
        var words = title.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        guard let first = words.firstIndex(where: { !core(of: $0).isEmpty }) else { return title }
        let names = knownNames.union(source.map(namesWritten(in:)) ?? [])
        let rest = words.indices.filter { $0 > first }
        words[first] = capitalized(words[first])
        if isTitleCase(rest.map { words[$0] }, names: names) {
            for index in rest {
                words[index] = lowercased(words[index], keeping: names)
            }
        }
        return words.joined(separator: " ")
    }

    /// Whether the words after the first read as Title Case: some are plainly capitalized, and the
    /// only lowercase ones are the small words Title Case leaves alone. A lowercase word with
    /// meaning ("build") says the title is in sentence case already.
    static func isTitleCase(_ words: [String], names: Set<String>) -> Bool {
        var capitalizedWords = 0
        for word in words {
            let core = core(of: word)
            switch Shape(core) {
            case .capitalized where !names.contains(core):
                capitalizedWords += 1
            case .lowercase where !smallWords.contains(core):
                return false
            default:
                break
            }
        }
        return capitalizedWords > 0
    }

    /// The first word, capitalized if it's a plain lowercase word ("run", not "iOS" or "`kt`").
    static func capitalized(_ word: String) -> String {
        let core = core(of: word)
        guard Shape(core) == .lowercase, let range = word.range(of: core) else { return word }
        return word.replacingCharacters(in: range, with: core.prefix(1).uppercased() + core.dropFirst())
    }

    private static func lowercased(_ word: String, keeping names: Set<String>) -> String {
        let core = core(of: word)
        guard Shape(core) == .capitalized, !names.contains(core), let range = word.range(of: core) else {
            return word
        }
        return word.replacingCharacters(in: range, with: core.lowercased())
    }

    /// The words `text` capitalizes where a sentence doesn't start: names as the user writes them.
    static func namesWritten(in text: String) -> Set<String> {
        var names: Set<String> = []
        for line in text.split(whereSeparator: \.isNewline) {
            var startsSentence = true
            for word in line.split(whereSeparator: \.isWhitespace) {
                let core = core(of: String(word))
                if !startsSentence, Shape(core) == .capitalized {
                    names.insert(core)
                }
                startsSentence = word.last.map { ".!?:".contains($0) } ?? false
            }
        }
        return names
    }

    /// A word without the punctuation around it: "(API)," is "API".
    static func core(of word: String) -> String {
        word.trimmingCharacters(in: .punctuationCharacters)
    }

    /// What a word's letters say about its case.
    enum Shape: Equatable {
        /// "Tests", "User's", "Follow-Up": a word Title Case capitalized.
        case capitalized
        /// "tests", "follow-up".
        case lowercase
        /// Acronyms, mixed case, code, numbers: kept as written.
        case other

        init(_ core: String) {
            let parts = core.split(separator: "-", omittingEmptySubsequences: false)
            guard !core.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(Self.isWordCharacter) }) else {
                self = .other
                return
            }
            if parts.allSatisfy({ $0.allSatisfy { $0.isLowercase || $0 == "'" } }) {
                self = .lowercase
            } else if parts.allSatisfy({ part in
                part.first?.isUppercase == true && part.dropFirst().allSatisfy { $0.isLowercase || $0 == "'" }
            }) {
                self = .capitalized
            } else {
                self = .other
            }
        }

        private static func isWordCharacter(_ character: Character) -> Bool {
            character.isLetter || character == "'"
        }
    }

    /// Words Title Case leaves lowercase.
    static let smallWords: Set<String> = [
        "a", "an", "and", "as", "at", "but", "by", "for", "from", "in", "into", "is", "it", "nor", "of", "off",
        "on", "onto", "or", "over", "per", "so", "the", "to", "up", "via", "vs", "with", "yet",
    ]

    /// Names that keep their capital wherever they are, so a title needn't have got them from the
    /// message. Only ones that aren't also everyday words.
    static let knownNames: Set<String> = [
        "I", "Swift", "Xcode", "Python", "Rust", "Ruby", "Java", "Kotlin", "JavaScript", "TypeScript", "React",
        "Linux", "Windows", "Android", "Apple", "Mac", "Docker", "Kubernetes", "Claude", "Codex", "Markdown",
        "Postgres", "Redis", "Tailwind", "Slack", "Sentry", "Homebrew",
    ]
}
