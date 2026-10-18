import Foundation

/// Files named in a prompt's text as `@path`, or `@"path with spaces"`, at the start of a word.
/// Agents read these as references to the files; Native also sends each one that exists as a
/// `resource_link`, so the agent gets the file whether or not it parses mentions.
public enum FileMention {
    /// The mention of `path`, quoted when it has spaces.
    public static func mention(of path: String) -> String {
        path.contains(where: \.isWhitespace) ? "@\"\(path)\"" : "@\(path)"
    }

    /// The paths mentioned in `text`, in order, as written.
    public static func paths(in text: String) -> [String] {
        var paths: [String] = []
        var index = text.startIndex
        while let at = text[index...].firstIndex(of: "@") {
            index = text.index(after: at)
            // Only at the start of a word, so `name@example.com` isn't one.
            if at > text.startIndex, !text[text.index(before: at)].isWhitespace {
                continue
            }
            if text[index...].first == "\"" {
                let start = text.index(after: index)
                guard let end = text[start...].firstIndex(of: "\"") else { break }
                paths.append(String(text[start..<end]))
                index = text.index(after: end)
            } else {
                let end = text[index...].firstIndex(where: \.isWhitespace) ?? text.endIndex
                if end > index {
                    paths.append(String(text[index..<end]))
                }
                index = end
            }
        }
        return paths
    }
}

extension PromptAttachment {
    /// The files `text` mentions that exist, relative to `root` unless the path is absolute. A
    /// mention ending a sentence ("see @README.md.") still finds the file.
    public static func mentions(in text: String, relativeTo root: URL) -> [PromptAttachment] {
        FileMention.paths(in: text).compactMap { path in
            var candidate = Substring(path)
            while !candidate.isEmpty {
                let url =
                    candidate.hasPrefix("/")
                    ? URL(filePath: String(candidate)) : root.appending(path: String(candidate))
                if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                    return PromptAttachment(
                        url: url.standardizedFileURL, content: .reference, byteCount: nil, origin: .mentioned)
                }
                guard let last = candidate.last, ".,;:!?)]}'\"".contains(last) else { return nil }
                candidate = candidate.dropLast()
            }
            return nil
        }
    }
}
