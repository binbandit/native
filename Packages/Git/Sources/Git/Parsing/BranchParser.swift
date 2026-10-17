import Foundation

enum BranchParser {
    static func parse(_ output: String) -> [Branch] {
        var branches: [Branch] = []
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 8 else { continue }
            // Skip symbolic refs such as refs/remotes/origin/HEAD.
            guard fields[7].isEmpty else { continue }
            branches.append(
                Branch(
                    name: fields[1],
                    reference: fields[0],
                    isRemote: fields[0].hasPrefix("refs/remotes/"),
                    isCurrent: fields[4] == "*",
                    commit: fields[2],
                    upstream: fields[3].isEmpty ? nil : fields[3],
                    worktreePath: fields[6].isEmpty ? nil : URL(filePath: fields[6], directoryHint: .isDirectory),
                    committerDate: TimeInterval(fields[5]).map(Date.init(timeIntervalSince1970:))
                ))
        }
        // Stable: locals first, keeping git's date order within each group.
        return branches.filter { !$0.isRemote } + branches.filter(\.isRemote)
    }
}
