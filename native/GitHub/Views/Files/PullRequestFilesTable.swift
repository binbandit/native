import CoreGraphics

/// Where each row of Files Changed sits, so only the rows near what's visible are built and the
/// list never measures rows to find its place. Diff blocks are exactly their lines and footers a
/// fixed height; other rows use what they measured, or what the last row of their kind measured,
/// until they've been on screen.
struct PullRequestFilesTable {
    /// Each row's top, then the bottom of the last.
    let offsets: [CGFloat]
    /// Whether each row's height is known without measuring it.
    let isExact: [Bool]

    /// What a row's height is estimated from before it's measured.
    enum Kind: Hashable {
        case header, foldedHeader, hunkHeader, notice, thread, draft, wrappedBlock

        init?(_ row: PullRequestFilesRow) {
            switch row.kind {
            case .header: self = row.slice == .single ? .foldedHeader : .header
            case .hunkHeader: self = .hunkHeader
            case .loading, .missing, .large: self = .notice
            case .thread: self = .thread
            case .draft: self = .draft
            case .block: self = .wrappedBlock
            case .footer: return nil
            }
        }

        /// Close enough that rows shift little when they're measured.
        var fallback: CGFloat {
            switch self {
            case .header: 40
            case .foldedHeader: 56
            case .hunkHeader: 24
            case .notice: 56
            case .thread: 160
            case .draft: 240
            case .wrappedBlock: 300
            }
        }
    }

    /// - Parameter exactHeight: A row's height when it's known without building it.
    init(
        rows: [PullRequestFilesRow], measured: [String: CGFloat], estimates: [Kind: CGFloat],
        exactHeight: (PullRequestFilesRow) -> CGFloat?
    ) {
        var offsets: [CGFloat] = []
        var isExact: [Bool] = []
        offsets.reserveCapacity(rows.count + 1)
        isExact.reserveCapacity(rows.count)
        var y: CGFloat = 0
        for row in rows {
            offsets.append(y)
            let exact = exactHeight(row)
            isExact.append(exact != nil)
            if let height = exact ?? measured[row.id] {
                y += height
            } else if let kind = Kind(row) {
                y += estimates[kind] ?? kind.fallback
            }
        }
        offsets.append(y)
        self.offsets = offsets
        self.isExact = isExact
    }

    var total: CGFloat {
        offsets.last ?? 0
    }

    /// The rows that overlap `top..<bottom`.
    func rows(from top: CGFloat, to bottom: CGFloat) -> Range<Int> {
        let count = offsets.count - 1
        guard count > 0, bottom > top else { return 0..<0 }
        let first = lastRow(startingAtOrAbove: top)
        let last = lastRow(startingAtOrAbove: bottom)
        return first..<min(last + 1, count)
    }

    /// The last row whose top is at or above `y`, by binary search.
    private func lastRow(startingAtOrAbove y: CGFloat) -> Int {
        var low = 0
        var high = offsets.count - 2
        while low < high {
            let middle = (low + high + 1) / 2
            if offsets[middle] <= y { low = middle } else { high = middle - 1 }
        }
        return low
    }
}
