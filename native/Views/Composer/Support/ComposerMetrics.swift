import CoreGraphics

/// Composer-only sizes, measured from Factory, that no other feature shares.
nonisolated enum ComposerMetrics {
    /// The slash-command list's cap (Factory `SUGGESTION_LIST_MAX_HEIGHT`).
    static let suggestionListMaxHeight: CGFloat = 272
    /// The plan section's cap (Factory `MAX_PLAN_HEIGHT`).
    static let planMaxHeight: CGFloat = 240
    /// The editor grows to this, then scrolls (Factory `RichTextArea maxHeight`).
    static let editorMaxHeight: CGFloat = 250
    /// NSTextView pads each line by this much on both sides; the editor's insets subtract it so
    /// the text lands on Factory's 12pt.
    static let editorLineFragmentPadding: CGFloat = 5
    /// Opens 13pt lines up to Factory's 1.5 line height.
    static let editorLineSpacing: CGFloat = 4
    /// The model picker's search row (Factory `MODEL_SEARCH_ROW_HEIGHT`).
    static let modelSearchHeight: CGFloat = 34
    /// The model list's cap: Factory's 420 less the search row.
    static let modelListMaxHeight: CGFloat = 420 - modelSearchHeight
    /// Wider than Factory's 240pt menu, because agents describe their models in a sentence rather
    /// than a price multiplier.
    static let modelPickerWidth: CGFloat = 340
    /// A column of the keyboard shortcuts sheet.
    static let shortcutsColumnWidth: CGFloat = 340
    /// Queued-message row actions (Factory `QueuedMessageActionButton`, 18px).
    static let rowActionSize: CGFloat = 18
    /// Plan step indicators: a 10pt dot in a 12pt slot (Factory `TodoStatusIndicator`).
    static let stepDotSize: CGFloat = 10
    static let stepSlotWidth: CGFloat = 12
}
