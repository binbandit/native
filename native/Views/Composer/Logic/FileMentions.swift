import Foundation

/// Files as @-mentions in a prompt, which agents read as references to them.
enum FileMentions {
    /// The draft with a mention of each file appended: relative to `root` when inside it, and
    /// quoted when the path has spaces.
    static func draft(_ draft: String, mentioning urls: [URL], relativeTo root: URL) -> String {
        guard !urls.isEmpty else { return draft }
        let rootPath = root.resolvingSymlinksInPath().path(percentEncoded: false)
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        let mentions = urls.map { url in
            let path = url.resolvingSymlinksInPath().path(percentEncoded: false)
            let shown = path.hasPrefix(rootPrefix) ? String(path.dropFirst(rootPrefix.count)) : path
            return shown.contains(where: \.isWhitespace) ? "@\"\(shown)\"" : "@\(shown)"
        }
        let separator = draft.isEmpty || draft.last?.isWhitespace == true ? "" : " "
        return draft + separator + mentions.joined(separator: " ") + " "
    }
}
