import Foundation

/// `git worktree list --porcelain -z`.
enum WorktreeParser {
    static func parse(_ output: String) -> [Worktree] {
        var worktrees: [Worktree] = []
        var current: Worktree?
        for token in output.split(separator: "\0", omittingEmptySubsequences: false) {
            if token.isEmpty {
                // A blank token ends a record.
                if let worktree = current { worktrees.append(worktree) }
                current = nil
                continue
            }
            let parts = token.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
            let key = parts[0]
            let value = parts.count > 1 ? String(parts[1]) : ""
            if key == "worktree" {
                if let worktree = current { worktrees.append(worktree) }
                current = Worktree(
                    path: URL(filePath: value, directoryHint: .isDirectory), head: nil, branch: nil,
                    isMain: worktrees.isEmpty, isBare: false, isDetached: false, isLocked: false, isPrunable: false
                )
                continue
            }
            switch key {
            case "HEAD": current?.head = value.allSatisfy({ $0 == "0" }) ? nil : value
            case "branch":
                current?.branch = value.hasPrefix("refs/heads/") ? String(value.dropFirst("refs/heads/".count)) : value
            case "detached": current?.isDetached = true
            case "bare": current?.isBare = true
            case "locked": current?.isLocked = true
            case "prunable": current?.isPrunable = true
            default: break
            }
        }
        if let worktree = current { worktrees.append(worktree) }
        return worktrees
    }
}
