import Foundation
import GitHub

/// Picking lines for a comment by dragging in the gutter, and the lines a conversation covers while
/// it's hovered or being replied to.
extension PullRequestPageModel {
    /// The Files Changed list's content, where blocks report where they sit. It scrolls with the
    /// blocks, so their places in it hold still while a drag crosses them.
    static let filesSpace = "pullRequestFiles"

    func placeBlock(_ path: String, _ hunk: DiffHunk, _ range: Range<Int>, minY: CGFloat) {
        blockOrigins[Self.hunkKey(path, hunk), default: [:]][range.lowerBound] = (range.upperBound, minY)
    }

    /// The hunk's line at `y` in the list: before the first line when above the hunk's first block,
    /// past the last when below its last block, and the line above a conversation in between.
    func hunkLine(at y: CGFloat, _ path: String, _ hunk: DiffHunk, lineHeight: CGFloat) -> Int? {
        guard let origins = blockOrigins[Self.hunkKey(path, hunk)], lineHeight > 0,
            let first = origins.min(by: { $0.key < $1.key })
        else { return nil }
        guard y >= first.value.minY else { return first.key - 1 }
        guard let block = origins.filter({ $0.value.minY <= y }).max(by: { $0.value.minY < $1.value.minY }) else {
            return nil
        }
        let index = block.key + Int(((y - block.value.minY) / lineHeight).rounded(.down))
        if index < block.value.end { return index }
        return block.value.end == hunk.lines.count ? hunk.lines.count : block.value.end - 1
    }

    /// Follows a drag in the gutter from `startY` to `y`: the pick starts on the line pressed and
    /// reaches as far toward the pointer as GitHub allows.
    func dragSelection(_ path: String, _ hunk: DiffHunk, from startY: CGFloat, to y: CGFloat, lineHeight: CGFloat) {
        guard page?.isOpen == true, let start = hunkLine(at: startY, path, hunk, lineHeight: lineHeight),
            let current = hunkLine(at: y, path, hunk, lineHeight: lineHeight)
        else { return }
        var selection = lineSelection
        if selection?.path != path || selection?.hunk.id != hunk.id || selection?.start != start {
            selection = ReviewLineSelection(path: path, hunk: hunk, line: start)
        }
        selection?.extend(to: current)
        if selection != lineSelection { lineSelection = selection }
    }

    /// Opens a comment on the picked lines.
    func endDragSelection() {
        guard let selection = lineSelection else { return }
        lineSelection = nil
        beginComment(at: selection.anchor)
    }

    func cancelLineSelection() {
        lineSelection = nil
    }

    /// The hunk's line indices being picked.
    func selectedLines(in path: String, hunk: DiffHunk) -> Set<Int> {
        guard let selection = lineSelection, selection.path == path, selection.hunk.id == hunk.id else { return [] }
        return Set(selection.lines)
    }

    /// The hunk's line indices the highlighted conversation is about.
    func highlightedThreadLines(in path: String, hunk: DiffHunk) -> Set<Int> {
        guard let id = highlightedThread, let thread = threads(in: path).first(where: { $0.id == id }),
            let anchor = thread.anchor
        else { return [] }
        return lines(covering: anchor, in: hunk)
    }

    /// The hunk's line indices a comment's anchor covers: its side's lines from its first to last.
    func lines(covering anchor: ReviewAnchor, in hunk: DiffHunk) -> Set<Int> {
        let covered = (anchor.startLine ?? anchor.line)...anchor.line
        return Set(
            hunk.lines.indices.filter { index in
                guard let target = hunk.lines[index].anchor else { return false }
                return target.side == anchor.side && covered.contains(target.line)
            })
    }

    func isExpanded(_ thread: ReviewThread) -> Bool {
        threadExpansion[thread.id] ?? !thread.isResolved
    }

    func toggleExpanded(_ thread: ReviewThread) {
        threadExpansion[thread.id] = !isExpanded(thread)
    }
}
