import Foundation

/// `git diff --numstat -z`, keyed by the (new) path.
enum NumstatParser {
    static func parse(_ output: String) -> [String: LineStats] {
        var result: [String: LineStats] = [:]
        var tokens = output.split(separator: "\0", omittingEmptySubsequences: false)[...]
        while let token = tokens.popFirst() {
            // <added>\t<deleted>\t<path>, or for a rename <added>\t<deleted>\t then the old and new
            // paths as tokens of their own.
            let fields = token.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard fields.count == 3 else { continue }
            let path: Substring
            if fields[2].isEmpty {
                guard tokens.popFirst() != nil, let new = tokens.popFirst() else { break }
                path = new
            } else {
                path = fields[2]
            }
            // Binary files count as "-".
            if let additions = Int(fields[0]), let deletions = Int(fields[1]) {
                result[String(path)] = LineStats(additions: additions, deletions: deletions)
            } else {
                result[String(path)] = LineStats(isBinary: true)
            }
        }
        return result
    }
}
