import Foundation

/// The local branch a pull request is checked out on for a task: `pr-<number>-<title>`, readable
/// in the sidebar and in `git branch`, and never the head's own name, which the main checkout may
/// already use.
public enum PullRequestTaskBranch {
    /// `pr-<number>-<title in kebab case>`, at most `maxLength` characters, cut between words.
    public static func name(number: Int, title: String, maxLength: Int = 40) -> String {
        let prefix = "pr-\(number)"
        let words = slugWords(title)
        var name = prefix
        for word in words {
            let next = "\(name)-\(word)"
            guard next.count <= maxLength else {
                // A first word too long to fit whole is cut rather than dropped, so the name says
                // something.
                if name == prefix, maxLength - prefix.count > 4 {
                    name = String(next.prefix(maxLength))
                }
                break
            }
            name = next
        }
        return name
    }

    /// The title's words as lowercase ASCII letters and digits; accents are folded, and anything
    /// else separates words.
    static func slugWords(_ title: String) -> [String] {
        let folded = title.folding(
            options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX"))
        var words: [String] = []
        var word = ""
        for scalar in folded.unicodeScalars {
            if ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) {
                word.unicodeScalars.append(scalar)
            } else if !word.isEmpty {
                words.append(word)
                word = ""
            }
        }
        if !word.isEmpty { words.append(word) }
        return words
    }
}
