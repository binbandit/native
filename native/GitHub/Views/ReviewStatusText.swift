import GitHub
import SwiftUI

/// Where an open pull request stands with reviewers: Draft, Approved,
/// Changes requested or Review required. Shows nothing when there's nothing to say.
struct ReviewStatusText: View {
    let pullRequest: PullRequestSummary

    var body: some View {
        if let status = Self.status(of: pullRequest) {
            Text(status.label)
                .foregroundStyle(status.tint)
                .lineLimit(1)
                .fixedSize()
        }
    }

    static func status(of pullRequest: PullRequestSummary) -> (label: String, tint: Color)? {
        guard pullRequest.state == .open else { return nil }
        if pullRequest.isDraft {
            return ("Draft", .dsTextTertiary)
        }
        return switch pullRequest.reviewDecision {
        case .approved: ("Approved", .dsSuccess)
        case .changesRequested: ("Changes requested", .dsDanger)
        case .reviewRequired: ("Review required", .dsTextTertiary)
        case .other, nil: nil
        }
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Review status") {
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            ForEach(PullRequestPreviewFixtures.inbox.all) { pullRequest in
                HStack {
                    Text(pullRequest.reference)
                        .foregroundStyle(.dsTextTertiary)
                    ReviewStatusText(pullRequest: pullRequest)
                }
                .font(.dsBody)
            }
        }
    }
}
#endif
