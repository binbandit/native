import Foundation

/// Files as `@` mentions in a prompt, which agents read as references to them.
enum FileMentions {
    /// The mention of a project-relative path: `@path`, quoted when the path has spaces.
    static func mention(of path: String) -> String {
        path.contains(where: \.isWhitespace) ? "@\"\(path)\"" : "@\(path)"
    }

    /// `url`'s path relative to `root` when it's inside it, otherwise the full path.
    static func path(of url: URL, relativeTo root: URL) -> String {
        let rootPath = root.resolvingSymlinksInPath().path(percentEncoded: false)
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        let path = url.resolvingSymlinksInPath().path(percentEncoded: false)
        return path.hasPrefix(rootPrefix) ? String(path.dropFirst(rootPrefix.count)) : path
    }

    /// The draft with a mention of each file appended, as when files are dropped on the composer.
    static func draft(_ draft: String, mentioning urls: [URL], relativeTo root: URL) -> String {
        guard !urls.isEmpty else { return draft }
        let mentions = urls.map { mention(of: path(of: $0, relativeTo: root)) }
        let separator = draft.isEmpty || draft.last?.isWhitespace == true ? "" : " "
        return draft + separator + mentions.joined(separator: " ") + " "
    }
}
