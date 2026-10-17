import Foundation

/// Gitignore-style globs for picking files: a pattern without a slash matches a file name at any
/// depth (`.env*`), one with a slash matches the path from the repository root (`config/*.json`).
struct FilePatterns: Sendable {
    let patterns: [String]

    func matches(_ path: String) -> Bool {
        let name = path.split(separator: "/").last.map(String.init) ?? path
        return patterns.contains { pattern in
            let anchored = pattern.hasPrefix("/") ? String(pattern.dropFirst()) : pattern
            if anchored.contains("/") {
                return fnmatch(anchored, path, FNM_PATHNAME | FNM_PERIOD) == 0
            }
            return fnmatch(anchored, name, 0) == 0
        }
    }
}
