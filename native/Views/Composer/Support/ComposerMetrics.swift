import CoreGraphics

/// Composer-only sizes that no other feature shares.
nonisolated enum ComposerMetrics {
    /// The slash-command list's cap.
    static let suggestionListMaxHeight: CGFloat = 272
    /// The plan section's cap.
    static let planMaxHeight: CGFloat = 240
    /// The editor grows to this, then scrolls.
    static let editorMaxHeight: CGFloat = 250
    /// NSTextView pads each line by this much on both sides; the editor's insets subtract it so
    /// the text lands on a 12pt inset.
    static let editorLineFragmentPadding: CGFloat = 5
    /// Opens 13pt lines up to a 1.5 line height.
    static let editorLineSpacing: CGFloat = 4
    /// The rich-text editor's leading increase that draws the same lines as `editorLineSpacing`.
    /// Measured, since it doesn't follow from the spacing alone: scripts/tests/composer-caret.sh
    /// checks that both editors draw a draft alike.
    static let editorRichLineLeading: CGFloat = 3.5
    /// The model picker's search row.
    static let modelSearchHeight: CGFloat = 34
    /// The model list's cap: 420 less the search row.
    static let modelListMaxHeight: CGFloat = 420 - modelSearchHeight
    /// Wider than a plain menu, because agents describe their models in a sentence.
    static let modelPickerWidth: CGFloat = 340
    /// A column of the keyboard shortcuts sheet.
    static let shortcutsColumnWidth: CGFloat = 340
    /// Queued-message row actions.
    static let rowActionSize: CGFloat = 18
    /// Plan step indicators: a 10pt dot in a 12pt slot.
    static let stepDotSize: CGFloat = 10
    static let stepSlotWidth: CGFloat = 12
    /// An attachment chip's thumbnail: small, since the chip names the file beside it.
    static let attachmentThumbnail: CGFloat = 28
    /// Long names truncate in the middle past this.
    static let attachmentChipMaxWidth: CGFloat = 240
    /// Three and a half rows of chips (36pt each, 6pt apart, under 8pt padding): past three rows,
    /// the half row shows there's more to scroll to.
    static let attachmentsMaxHeight: CGFloat = 152
}
