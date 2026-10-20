import Foundation

/// A session's working directory as agents record it. The same folder can arrive under more than one
/// spelling: Codex keeps a session started in `/tmp/x` as `/private/tmp/x` and lists it only for that
/// path, while other agents keep the path as given. So folders are listed under every spelling and
/// compared by the folder they resolve to.
public enum SessionFolder {
    /// The paths to ask `session/list` for: the path as given, then its resolved form when that
    /// differs (`/tmp/x` and `/private/tmp/x`).
    public static func listingPaths(for path: String) -> [String] {
        let path = trimmed(path)
        let resolved = resolved(path)
        return resolved == path ? [path] : [path, resolved]
    }

    /// Whether two paths are the same folder, whichever spelling each one uses. The same spelling
    /// needs no look at the disk, which views ask about for every row.
    public static func isSame(_ first: String, _ second: String) -> Bool {
        let first = trimmed(first)
        let second = trimmed(second)
        return first == second || resolved(first) == resolved(second)
    }

    /// Whether `path` is `folder` or inside it.
    public static func contains(_ folder: String, _ path: String) -> Bool {
        let folder = resolved(trimmed(folder))
        let path = resolved(trimmed(path))
        return path == folder || path.hasPrefix(folder == "/" ? "/" : folder + "/")
    }

    /// The path with every symlink resolved (`/private/tmp`, not `/tmp`, unlike
    /// `resolvingSymlinksInPath()`). Only the part that exists can be resolved, so a removed folder
    /// keeps its missing components on its resolved parent.
    private static func resolved(_ path: String) -> String {
        var existing = (path as NSString).standardizingPath
        var missing: [String] = []
        while existing.count > 1 {
            if let real = realPath(existing) {
                return missing.reversed().reduce(real) { ($0 as NSString).appendingPathComponent($1) }
            }
            missing.append((existing as NSString).lastPathComponent)
            existing = (existing as NSString).deletingLastPathComponent
        }
        return (path as NSString).standardizingPath
    }

    private static func realPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// Without the trailing slash a folder URL's path keeps, which agents don't record.
    private static func trimmed(_ path: String) -> String {
        path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
