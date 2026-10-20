import GitHub
import SwiftUI

/// What the agent was given with the first question, or with a follow-up after new commits. A
/// pull request too large to send whole says exactly what was left out and where the agent
/// finds it.
struct PullRequestAskContextNote: View {
    let inclusion: PullRequestAskInclusion
    let isRefresh: Bool

    var body: some View {
        if inclusion.isWhole {
            Label(
                (isRefresh ? "Brought in the new commits: " : "Sent with your question: ") + summary,
                systemImage: "doc.text"
            )
            .font(.dsCaption)
            .foregroundStyle(.dsTextTertiary)
            .labelStyle(PullRequestAskCaptionLabelStyle())
        } else {
            NoticeBanner(
                tone: .info, systemImage: "doc.text",
                title: isRefresh ? "Brought in the new commits, in part" : "Too large to send whole",
                detail: "Sent with your question: " + summary,
                footnote: inclusion.leftOut.joined(separator: " ")
            ) {
                EmptyView()
            }
        }
    }

    /// The summary as the rest of a sentence.
    private var summary: String {
        inclusion.summary.prefix(1).lowercased() + inclusion.summary.dropFirst()
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Ask context note") {
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            PullRequestAskContextNote(inclusion: PullRequestAskPreviewFixtures.inclusion, isRefresh: false)
            PullRequestAskContextNote(inclusion: PullRequestAskPreviewFixtures.inclusion, isRefresh: true)
            PullRequestAskContextNote(inclusion: PullRequestAskPreviewFixtures.partialInclusion, isRefresh: false)
        }
        .frame(width: PullRequestAskMetrics.panelIdealWidth)
    }
}
#endif
