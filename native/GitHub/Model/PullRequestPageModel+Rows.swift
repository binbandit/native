import Foundation
import GitHub

/// Files Changed as rows, and how each file's long lines show: cut off at the pane edge with a
/// "…" to open them one at a time, or wrapped for the whole file.
extension PullRequestPageModel {
    /// Blocks stay short, so scrolling lays out a little at a time.
    static let blockLines =
        UserDefaults.standard.integer(forKey: "gitHubExperimentBlockLines") > 0
        ? UserDefaults.standard.integer(forKey: "gitHubExperimentBlockLines") : 48

    var rows: [PullRequestFilesRow] {
        var rows: [PullRequestFilesRow] = []
        for file in files {
            let path = file.path
            if isCollapsed(file) {
                rows.append(PullRequestFilesRow(id: "h:\(path)", path: path, kind: .header(file), slice: .single))
                continue
            }
            rows.append(PullRequestFilesRow(id: "h:\(path)", path: path, kind: .header(file), slice: .top))
            func add(_ id: String, _ kind: PullRequestFilesRow.Kind) {
                rows.append(PullRequestFilesRow(id: "\(id):\(path)", path: path, kind: kind, slice: .middle))
            }
            let threads = threads(in: path)
            if let patch = patches[path] {
                if let reason = patch.missingPatchReason {
                    add("missing", .missing(reason))
                } else if isLarge(path), !loadedLargeDiffs.contains(path), threads.isEmpty {
                    add("large", .large(lines: lineCount(path)))
                } else {
                    for (index, hunk) in (hunks[path] ?? []).enumerated() {
                        add("hunk\(index)", .hunkHeader(hunk))
                        for segment in segments(of: hunk, in: path, threads: threads) {
                            add("b\(index).\(segment.lowerBound)", .block(hunk, range: segment))
                            guard let last = segment.last, let target = hunk.lines[last].anchor else { continue }
                            for thread in threads
                            where thread.anchor?.side == target.side && thread.anchor?.line == target.line {
                                rows.append(
                                    PullRequestFilesRow(
                                        id: "t:\(thread.id)", path: path, kind: .thread(thread, showsAnchor: false),
                                        slice: .middle))
                            }
                            if let draft, draft.anchor.path == path, draft.anchor.side == target.side,
                                draft.anchor.line == target.line
                            {
                                add("draft", .draft)
                            }
                        }
                    }
                }
                for thread in outdatedThreads(threads, in: path) {
                    rows.append(
                        PullRequestFilesRow(
                            id: "t:\(thread.id)", path: path, kind: .thread(thread, showsAnchor: true), slice: .middle))
                }
            } else if patchesComplete {
                add("missing", .missing(.tooLarge))
            } else {
                add("loading", .loading)
            }
            rows.append(PullRequestFilesRow(id: "f:\(path)", path: path, kind: .footer, slice: .bottom))
        }
        return rows
    }

    /// The hunk's lines cut into blocks: after every line with something under it, and every
    /// `blockLines` lines.
    private func segments(of hunk: DiffHunk, in path: String, threads: [ReviewThread]) -> [Range<Int>] {
        let anchored = Set(threads.compactMap(\.anchor).map { "\($0.side.rawValue)\($0.line)" })
        let draftKey = draft.flatMap { $0.anchor.path == path ? "\($0.anchor.side.rawValue)\($0.anchor.line)" : nil }
        var segments: [Range<Int>] = []
        var start = 0
        for index in hunk.lines.indices {
            let key = hunk.lines[index].anchor.map { "\($0.side.rawValue)\($0.line)" }
            let isFull = index + 1 - start >= Self.blockLines
            if isFull || key.map({ anchored.contains($0) || $0 == draftKey }) == true {
                segments.append(start..<(index + 1))
                start = index + 1
            }
        }
        if start < hunk.lines.count { segments.append(start..<hunk.lines.count) }
        return segments
    }

    /// Conversations whose lines are no longer in the diff, kept so nothing said goes missing.
    private func outdatedThreads(_ threads: [ReviewThread], in path: String) -> [ReviewThread] {
        let hunks = hunks[path] ?? []
        return threads.filter { thread in
            guard let anchor = thread.anchor else { return true }
            return !hunks.contains { $0.index(side: anchor.side, line: anchor.line) != nil }
        }
    }

    // MARK: - Long lines

    static let wrappedFilesKey = "gitHub.wrappedFiles"

    private func wrapKey(_ path: String) -> String {
        "\(reference.host)/\(reference.repository):\(path)"
    }

    func wraps(_ path: String) -> Bool {
        wrappedFiles.contains(wrapKey(path))
    }

    /// Wraps a file's long lines, or cuts them off again; remembered per file of the repository.
    func toggleWrapping(_ path: String) {
        let key = wrapKey(path)
        if wrappedFiles.remove(key) == nil { wrappedFiles.insert(key) }
        // A few hundred files is plenty to remember; the oldest go first.
        var stored = UserDefaults.standard.stringArray(forKey: Self.wrappedFilesKey) ?? []
        stored.removeAll { $0 == key }
        if wrappedFiles.contains(key) { stored.append(key) }
        UserDefaults.standard.set(Array(stored.suffix(300)), forKey: Self.wrappedFilesKey)
    }

    static func storedWrappedFiles() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: wrappedFilesKey) ?? [])
    }

    static func lineKey(_ path: String, _ hunk: DiffHunk, _ line: Int) -> String {
        "\(path)#\(hunk.id)#\(line)"
    }

    /// Shows one cut-off line whole.
    func expandLine(_ path: String, _ hunk: DiffHunk, _ line: Int) {
        expandedLines.insert(Self.lineKey(path, hunk, line))
    }

    /// Whether a line shows whole, wrapping: its file wraps, or it was opened.
    func isExpanded(_ path: String, _ hunk: DiffHunk, _ line: Int) -> Bool {
        wraps(path) || expandedLines.contains(Self.lineKey(path, hunk, line))
    }

    /// Whether a block draws line by line, so a line can wrap: when its file wraps, or a line in it
    /// was opened.
    func wrapsBlock(_ path: String, _ hunk: DiffHunk, _ range: Range<Int>) -> Bool {
        wraps(path) || range.contains { expandedLines.contains(Self.lineKey(path, hunk, $0)) }
    }
}
