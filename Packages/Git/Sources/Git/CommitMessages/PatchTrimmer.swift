import Foundation

/// Shrinks a unified diff to fit a small model's context while keeping every file represented:
/// header noise goes, then each file gets a fair share of the budget, with short files leaving
/// their unused share to longer ones.
public enum PatchTrimmer {
    /// Lines that cost tokens without saying anything about the change.
    private static let noisePrefixes = [
        "index ", "similarity index", "dissimilarity index", "old mode", "new mode", "deleted file mode",
        "new file mode", "--- ", "+++ ",
    ]

    public static func trim(_ patch: String, toCharacters budget: Int) -> String {
        let files = split(patch).map(stripNoise)
        let total = files.reduce(0) { $0 + $1.count }
        guard total > budget else { return files.joined() }

        var remaining = budget
        var trimmed = Array(repeating: "", count: files.count)
        // Smallest first, so each file's share is what's left divided by the files still waiting.
        let order = files.indices.sorted { files[$0].count < files[$1].count }
        for (position, index) in order.enumerated() {
            let share = remaining / (order.count - position)
            trimmed[index] = truncate(files[index], to: share)
            remaining -= trimmed[index].count
        }
        return trimmed.joined()
    }

    /// Per-file chunks, each starting at its `diff --git` line.
    private static func split(_ patch: String) -> [String] {
        var lines = patch.split(separator: "\n", omittingEmptySubsequences: false)
        // A trailing newline ends the last line rather than starting another.
        if lines.last == "" { lines.removeLast() }
        var files: [String] = []
        for line in lines {
            if line.hasPrefix("diff --git ") || files.isEmpty {
                files.append("")
            }
            files[files.count - 1] += line + "\n"
        }
        return files
    }

    private static func stripNoise(_ file: String) -> String {
        file.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { line in !noisePrefixes.contains { line.hasPrefix($0) } }
            .joined(separator: "\n")
    }

    /// Whole lines up to `limit` characters, with a marker for what was cut.
    private static func truncate(_ file: String, to limit: Int) -> String {
        guard file.count > limit else { return file }
        var kept = ""
        var lines = file.split(separator: "\n", omittingEmptySubsequences: false)[...]
        while let line = lines.first, kept.count + line.count + 1 <= limit {
            kept += line + "\n"
            lines.removeFirst()
        }
        let cut = lines.filter { !$0.isEmpty }.count
        return cut > 0 ? kept + "[\(cut) more lines]\n" : kept
    }
}
