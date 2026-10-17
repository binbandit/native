import Foundation

/// `git status --porcelain=v2 --branch -z`.
enum StatusParser {
    static func parse(_ output: String) throws(GitError) -> (branch: BranchStatus, changes: [FileChange]) {
        var head = BranchStatus.Head.detached
        var commit: String?
        var upstream: String?
        var counts: (ahead: Int, behind: Int)?
        var changes: [FileChange] = []

        var records = output.split(separator: "\0", omittingEmptySubsequences: true)[...]
        while let record = records.popFirst() {
            guard let type = record.first else { continue }
            switch type {
            case "#":
                let header = record.dropFirst(2)
                if let value = header.value(after: "branch.oid ") {
                    commit = value == "(initial)" ? nil : String(value)
                } else if let value = header.value(after: "branch.head ") {
                    head = value == "(detached)" ? .detached : .branch(String(value))
                } else if let value = header.value(after: "branch.upstream ") {
                    upstream = String(value)
                } else if let value = header.value(after: "branch.ab ") {
                    let parts = value.split(separator: " ")
                    guard parts.count == 2, let ahead = Int(parts[0].dropFirst()), let behind = Int(parts[1].dropFirst()) else {
                        throw .unexpectedOutput("status header \(record)")
                    }
                    counts = (ahead, behind)
                }
            case "1":
                // 1 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <path>
                let fields = record.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: false)
                guard fields.count == 9 else { throw .unexpectedOutput("status entry \(record)") }
                changes += entries(xy: fields[1], submodule: fields[2], path: String(fields[8]), originalPath: nil)
            case "2":
                // 2 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <X><score> <path>, then the original path.
                let fields = record.split(separator: " ", maxSplits: 9, omittingEmptySubsequences: false)
                guard fields.count == 10, let original = records.popFirst() else { throw .unexpectedOutput("status entry \(record)") }
                changes += entries(xy: fields[1], submodule: fields[2], path: String(fields[9]), originalPath: String(original))
            case "u":
                // u <XY> <sub> <m1> <m2> <m3> <mW> <h1> <h2> <h3> <path>
                let fields = record.split(separator: " ", maxSplits: 10, omittingEmptySubsequences: false)
                guard fields.count == 11 else { throw .unexpectedOutput("status entry \(record)") }
                changes.append(FileChange(path: String(fields[10]), kind: .conflicted, area: .conflicted, isSubmodule: fields[2].first == "S"))
            case "?":
                changes.append(FileChange(path: String(record.dropFirst(2)), kind: .untracked, area: .untracked))
            default:
                // "!" (ignored) only appears when asked for.
                continue
            }
        }

        let branch = BranchStatus(
            head: head,
            commit: commit,
            upstream: upstream,
            ahead: counts?.ahead ?? 0,
            behind: counts?.behind ?? 0,
            // git leaves out the counts when the upstream ref is missing.
            isUpstreamGone: upstream != nil && counts == nil
        )
        return (branch, changes)
    }

    /// The staged and unstaged halves of an ordinary or renamed entry.
    private static func entries(xy: Substring, submodule: Substring, path: String, originalPath: String?) -> [FileChange] {
        let codes = Array(xy)
        guard codes.count == 2 else { return [] }
        let isSubmodule = submodule.first == "S"
        var result: [FileChange] = []
        if let kind = kind(for: codes[0]) {
            result.append(FileChange(path: path, originalPath: originalPath, kind: kind, area: .staged, isSubmodule: isSubmodule))
        }
        if let kind = kind(for: codes[1]) {
            result.append(FileChange(path: path, kind: kind, area: .unstaged, isSubmodule: isSubmodule))
        }
        return result
    }

    private static func kind(for code: Character) -> FileChange.Kind? {
        switch code {
        case "M": .modified
        case "A": .added
        case "D": .deleted
        case "R": .renamed
        case "C": .copied
        case "T": .typeChanged
        case "U": .conflicted
        default: nil
        }
    }
}

private extension Substring {
    func value(after prefix: String) -> Substring? {
        hasPrefix(prefix) ? dropFirst(prefix.count) : nil
    }
}
