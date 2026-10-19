import SwiftUI

/// A caption with its glyph on the first line, for wrapping notes.
struct PullRequestAskCaptionLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.xs) {
            configuration.icon
                .foregroundStyle(.dsTextTertiary)
            configuration.title
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
