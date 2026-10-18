import CodeThemes
import GitHub

/// The Files Changed tab's data. The file list loads whole (it's small); patches come a hundred
/// files at a time from REST, as the list scrolls to them, so a pull request with thousands of
/// files opens as fast as a small one.
extension PullRequestPageModel {
    var totalFiles: Int {
        page?.changedFiles ?? files.count
    }

    var viewedCount: Int {
        files.filter(\.isViewed).count
    }

    func isCollapsed(_ file: ChangedFile) -> Bool {
        if let override = collapseOverrides[file.path] { return override }
        return file.isViewed || file.isGenerated
    }

    func setCollapsed(_ collapsed: Bool, _ file: ChangedFile) {
        collapseOverrides[file.path] = collapsed
    }

    /// Loads the rest of the file list, for the tree.
    func loadAllFiles() async {
        while let cursor = filesCursor, let gitHub {
            do {
                let next = try await gitHub.cli().changedFiles(reference, after: cursor)
                files += next.files
                filesCursor = next.next
            } catch {
                patchError = error
                return
            }
        }
    }

    /// Makes sure `path`'s patch is loaded, fetching pages in order until it turns up. Several files
    /// can ask at once as the list scrolls; they wait for the page in flight rather than skip it.
    func loadPatch(for path: String) async {
        while patches[path] == nil, !patchesComplete, !Task.isCancelled {
            if isLoadingPatches {
                try? await Task.sleep(for: .milliseconds(150))
                continue
            }
            let before = patchPagesLoaded
            await loadNextPatchPage()
            if patchPagesLoaded == before { return }
        }
    }

    func loadNextPatchPage() async {
        guard let gitHub, !isLoadingPatches, !patchesComplete else { return }
        isLoadingPatches = true
        defer { isLoadingPatches = false }
        do {
            let page = try await gitHub.cli().filePatches(reference, page: patchPagesLoaded + 1)
            for patch in page {
                patches[patch.path] = patch
                hunks[patch.path] = patch.hunks
            }
            patchPagesLoaded += 1
            patchesComplete = page.count < 100 || patches.count >= totalFiles
            patchError = nil
        } catch {
            patchError = error
        }
    }

    /// Diffs past this many lines, or with minified lines, wait behind "Load Diff".
    static let largeDiffLines = 400
    static let minifiedLineLength = 1_000

    func isLarge(_ path: String) -> Bool {
        guard let hunks = hunks[path] else { return false }
        let lines = hunks.flatMap(\.lines)
        return lines.count > Self.largeDiffLines || lines.contains { $0.text.utf8.count > Self.minifiedLineLength }
    }

    func lineCount(_ path: String) -> Int {
        hunks[path]?.reduce(0) { $0 + $1.lines.count } ?? 0
    }

    static func hunkKey(_ path: String, _ hunk: DiffHunk) -> String {
        "\(path)#\(hunk.id)"
    }

    /// Highlights a file's hunks once, off the main thread; they draw plain until it's done.
    func highlight(_ path: String) async {
        guard let hunks = hunks[path], let language = CodeLanguage.forPath(path),
            highlightedPaths.insert(path).inserted
        else { return }
        for hunk in hunks {
            let code = hunk.lines.map { $0.kind == .noNewline ? "" : $0.text }.joined(separator: "\n")
            highlighted[Self.hunkKey(path, hunk)] = await CodeHighlightCache.shared.highlightLines(code, language: language)
        }
    }

    /// Marks a file viewed or not, on GitHub, so the mark follows the user to other machines. It
    /// changes at once and goes back if GitHub refuses.
    func setViewed(_ viewed: Bool, _ file: ChangedFile) async {
        guard let gitHub, let page, let index = files.firstIndex(of: file) else { return }
        files[index].viewedState = viewed ? .viewed : .unviewed
        collapseOverrides[file.path] = nil
        do {
            try await gitHub.cli().setViewed(viewed, path: file.path, on: page)
        } catch {
            if let index = files.firstIndex(where: { $0.path == file.path }) {
                files[index].viewedState = file.viewedState
            }
            actionError = error
        }
    }

    /// The text of the lines a comment covers, for suggestions: the head side's lines as they read.
    func lineText(for anchor: ReviewAnchor) -> String {
        guard let hunks = hunks[anchor.path] else { return "" }
        let first = anchor.startLine ?? anchor.line
        return hunks.flatMap(\.lines)
            .filter { line in
                guard let target = line.anchor, target.side == anchor.side else { return false }
                return (first...anchor.line).contains(target.line)
            }
            .map(\.text)
            .joined(separator: "\n")
    }

    /// The commented lines as unified diff, with a little context above, for agents.
    func excerpt(for anchor: ReviewAnchor) -> String {
        guard let hunks = hunks[anchor.path] else { return "" }
        for hunk in hunks {
            guard let end = hunk.index(side: anchor.side, line: anchor.line) else { continue }
            let start = anchor.startLine.flatMap { hunk.index(side: anchor.startSide ?? anchor.side, line: $0) } ?? end
            return hunk.excerpt(max(min(start, end) - 3, 0)...max(start, end))
        }
        return ""
    }
}

extension PullRequestPageModel {
    /// The comment being written widened to `line`, when that makes a valid range: the same hunk
    /// and side, as GitHub requires.
    func extendedDraft(to line: DiffHunk.Line, in hunk: DiffHunk, path: String) -> ReviewAnchor? {
        guard let draft, draft.anchor.path == path, let target = line.anchor, target.side == draft.anchor.side,
            hunk.index(side: target.side, line: draft.anchor.line) != nil
        else { return nil }
        let start = min(draft.anchor.startLine ?? draft.anchor.line, target.line)
        let end = max(draft.anchor.line, target.line)
        guard start != end || draft.anchor.startLine != nil else { return nil }
        return ReviewAnchor(path: path, side: target.side, line: end, startLine: start, startSide: target.side)
    }

    /// The hunk's line indices the comment being written covers.
    func draftLines(in path: String, hunk: DiffHunk) -> Set<Int> {
        guard let draft, draft.anchor.path == path else { return [] }
        let covered = (draft.anchor.startLine ?? draft.anchor.line)...draft.anchor.line
        return Set(
            hunk.lines.indices.filter { index in
                guard let anchor = hunk.lines[index].anchor else { return false }
                return anchor.side == draft.anchor.side && covered.contains(anchor.line)
            })
    }
}
