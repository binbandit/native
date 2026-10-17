import GitHub
import SwiftUI

/// The pull request glyph, colored by lifecycle the way GitHub does (Factory `PullRequestStateIcon`):
/// open green, draft gray, merged purple, closed red.
struct PullRequestStateIcon: View {
    let state: PullRequest.State
    let isDraft: Bool
    var size: CGFloat = DS.Size.statusGlyph

    var body: some View {
        PullRequestGlyph(kind: kind)
            // Lucide's 2-point stroke on its 24-point grid.
            .stroke(tint, style: StrokeStyle(lineWidth: size / 12, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .help(label)
            .accessibilityElement()
            .accessibilityLabel(label)
    }

    private var kind: PullRequestGlyph.Kind {
        switch state {
        case .merged: .merged
        case .closed: .closed
        case .open, .other: isDraft ? .draft : .open
        }
    }

    private var tint: Color {
        switch state {
        case .merged: .dsMerged
        case .closed: .dsDanger
        case .open: isDraft ? .dsTextTertiary : .dsSuccess
        case .other: .dsTextTertiary
        }
    }

    var label: String {
        switch state {
        case .merged: "Merged"
        case .closed: "Closed"
        case .open: isDraft ? "Draft" : "Open"
        case .other: "Pull request"
        }
    }
}
