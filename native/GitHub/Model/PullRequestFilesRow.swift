import GitHub

/// One row of Files Changed, which is a single flat lazy list across every file: file headers,
/// hunk headers, blocks of up to 48 diff lines, conversations and notices. Flat, so scrolling
/// creates only the rows on screen however big a file is; each row draws its slice of its file's
/// card.
struct PullRequestFilesRow: Identifiable {
    enum Kind {
        case header(ChangedFile)
        case loading
        case missing(FilePatch.MissingPatchReason)
        case large(lines: Int)
        case hunkHeader(DiffHunk)
        /// Lines `range` of hunk `hunk`.
        case block(DiffHunk, range: Range<Int>)
        case thread(ReviewThread, showsAnchor: Bool)
        case draft
        /// Closes the file's card.
        case footer
    }

    /// Where the row sits in its file's card, so it draws the right borders and corners.
    enum Slice {
        /// The header of an open file.
        case top
        case middle
        case bottom
        /// The header of a folded file: the whole card.
        case single
    }

    let id: String
    let path: String
    let kind: Kind
    let slice: Slice
}
