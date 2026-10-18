import GitHub
import SwiftUI

/// The description, then everything that happened in order (comments, reviews, commits, events),
/// then a box to comment. Line comments live with their lines on Files Changed; reviews here say
/// how many they had.
struct PullRequestConversationTab: View {
    let model: PullRequestPageModel
    let page: PullRequestPage

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DS.Space.lg) {
                PullRequestCommentCard(
                    author: page.author, date: page.createdAt, body: page.body, url: page.url, edited: false,
                    emptyText: "No description provided.")
                ForEach(page.timeline) { item in
                    PullRequestTimelineRow(item: item, model: model)
                }
                if page.timelineCursor != nil {
                    Button(model.isLoadingMoreTimeline ? "Loading…" : "Show \(page.timelineTotal - page.timeline.count) More") {
                        Task { await model.loadMoreTimeline() }
                    }
                    .buttonStyle(.ds(.secondary))
                    .disabled(model.isLoadingMoreTimeline)
                    .frame(maxWidth: .infinity)
                }
                if page.threadsTotal > 0 {
                    unresolvedThreadsLink
                }
                SeparatorLine()
                    .padding(.vertical, DS.Space.xs)
                PullRequestConversationComposer(model: model, page: page)
            }
            .padding(DS.Space.xl)
            .frame(maxWidth: DS.Size.contentColumn)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
    }

    /// Line comments live on Files Changed; this says how many need attention and goes there.
    private var unresolvedThreadsLink: some View {
        let open = page.threads.filter { !$0.isResolved }.count
        return Button {
            model.tab = .files
        } label: {
            Label(
                open > 0 ? "\(open) unresolved conversation\(open == 1 ? "" : "s") on Files Changed" : "All \(page.threadsTotal) line conversations are resolved",
                systemImage: "text.bubble")
        }
        .buttonStyle(.ds(.ghost))
    }
}
