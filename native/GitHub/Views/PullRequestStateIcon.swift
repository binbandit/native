import GitHub
import SwiftUI

/// The pull request glyph, colored by lifecycle the way GitHub does (Factory `PullRequestStateIcon`):
/// open green, draft gray, merged purple, closed red.
struct PullRequestStateIcon: View {
    let state: PullRequest.State
    let isDraft: Bool
    var size: CGFloat = DS.Size.statusGlyph

    var body: some View {
        Image(systemName: state == .merged ? "arrow.triangle.merge" : "arrow.triangle.pull")
            .font(.system(size: size * 0.86, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .help(label)
            .accessibilityLabel(label)
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
