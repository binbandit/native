import Foundation

/// `git diff-tree --raw -z`: `:<old mode> <new mode> <old id> <new id> <status>` then the path, or
/// for a rename or copy the old and new paths, each NUL-terminated.
enum RawDiffParser {
    static func parse(_ output: String) throws(GitError) -> [TreeChange] {
        var changes: [TreeChange] = []
        var tokens = output.split(separator: "\0", omittingEmptySubsequences: true)[...]
        while let header = tokens.popFirst() {
            let fields = header.dropFirst().split(separator: " ")
            guard header.first == ":", fields.count == 5, let code = fields[4].first, let path = tokens.popFirst()
            else {
                throw .unexpectedOutput("diff-tree entry \(header)")
            }
            // A gitlink's mode is 160000 on whichever side has it.
            let isSubmodule = fields[0] == "160000" || fields[1] == "160000"
            switch code {
            case "R", "C":
                guard let new = tokens.popFirst() else { throw .unexpectedOutput("diff-tree entry \(header)") }
                changes.append(
                    TreeChange(
                        path: String(new), originalPath: String(path), kind: code == "R" ? .renamed : .copied,
                        isSubmodule: isSubmodule))
            case "A": changes.append(TreeChange(path: String(path), kind: .added, isSubmodule: isSubmodule))
            case "D": changes.append(TreeChange(path: String(path), kind: .deleted, isSubmodule: isSubmodule))
            case "T": changes.append(TreeChange(path: String(path), kind: .typeChanged, isSubmodule: isSubmodule))
            default: changes.append(TreeChange(path: String(path), kind: .modified, isSubmodule: isSubmodule))
            }
        }
        return changes
    }
}
