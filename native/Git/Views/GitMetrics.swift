import SwiftUI

/// The Git feature's own dimensions, built from design system tokens.
nonisolated enum GitMetrics {
    /// Inspector column widths; the floor fits a path, its line counts and two row actions.
    static let inspectorMinWidth: CGFloat = 340
    static let inspectorIdealWidth: CGFloat = 420
    static let inspectorMaxWidth: CGFloat = 720
    /// The header row, as tall as the reference app's git panel tab row.
    static let headerHeight: CGFloat = 40
    /// The "N files changed" row (the reference app `ChangesSummary`, h-8).
    static let summaryHeight: CGFloat = DS.Size.controlMD
    /// File rows (the reference app `FileRow`, py-1 around 20pt text).
    static let rowHeight: CGFloat = DS.Size.controlSM
    /// The status glyph at a row's trailing edge (the reference app `size-3`).
    static let statusGlyph: CGFloat = DS.Size.navIcon
    /// The file list grows with its content up to this share of the column (at least
    /// `listMinHeight`); the diff takes the rest.
    static let listShare: CGFloat = 0.45
    static let listMinHeight: CGFloat = 120
    /// The commit popover.
    static let commitWidth: CGFloat = 420
    static let commitMessageHeight: CGFloat = 96
    static let commitFileListMaxHeight: CGFloat = 200
    /// Git's own output inside a notice scrolls past this height.
    static let noticeDetailMaxHeight: CGFloat = 96
    /// The dot-grid loader in headers and buttons, and in an empty pane.
    static let loaderSmall: CGFloat = DS.Size.statusGlyph
    static let loaderLarge: CGFloat = DS.Size.controlXS
    /// The checkbox square in the commit file list.
    static let checkbox: CGFloat = DS.Size.statusGlyph
    static let checkboxGlyph: CGFloat = 9
    /// Where `TextEditor` starts its text (NSTextView's line fragment padding), for placeholders.
    static let textEditorInset: CGFloat = 5
}
