/// How the toolbar shares the conversation's width between the task's title at its leading edge
/// and the centered well. The well gives way first, down to its compact width, so the title can
/// show whole; only then does the title truncate. A gap always stays between them.
public struct SessionToolToolbarLayout: Equatable, Sendable {
    public let titleWidth: Double
    public let wellWidth: Double

    /// - Parameters:
    ///   - titleOffset: Where the title starts, from the conversation's leading edge (window
    ///     controls and toolbar insets before it).
    ///   - titleIdealWidth: The title's width shown whole.
    ///   - wellWidth: The well's full width; `compactWellWidth` is as small as it gets.
    public init(
        conversationWidth: Double, titleOffset: Double, titleIdealWidth: Double, wellWidth: Double,
        compactWellWidth: Double, gap: Double, minimumTitleWidth: Double
    ) {
        let roomForWholeTitle = conversationWidth - 2 * (titleOffset + titleIdealWidth + gap)
        self.wellWidth = min(wellWidth, max(compactWellWidth, roomForWholeTitle))
        titleWidth = max(minimumTitleWidth, (conversationWidth - self.wellWidth) / 2 - titleOffset - gap)
    }
}
