import SwiftUI

/// The task scripts' own dimensions, built from design system tokens.
nonisolated enum TaskScriptMetrics {
    /// Script output scrolls past this height in the task's banner.
    static let outputMaxHeight: CGFloat = 160
    /// And past this in the log and the editor's test, which have more room.
    static let logOutputMaxHeight: CGFloat = 220
    /// The dot-grid loader beside a running script.
    static let loader: CGFloat = DS.Size.statusGlyph
    /// The script editor's text area.
    static let editorMinHeight: CGFloat = 180
    static let editorSheetWidth: CGFloat = 640
    /// The status bar's log popover.
    static let logWidth: CGFloat = 520
    static let logMaxHeight: CGFloat = 480
    /// How much of a failed script's output its notice shows.
    static let failureLines = 8
}
