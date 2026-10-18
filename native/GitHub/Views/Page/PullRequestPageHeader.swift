import GitHub
import SwiftUI

/// The top of a pull request's page (the reference app `PullRequestHeader`): back, the title and number, then
/// one line of where it stands: state, branch into base, checks, review decision and whether it can
/// merge. The review and merge actions sit on the right.
struct PullRequestPageHeader: View {
    let model: PullRequestPageModel
    let page: PullRequestPage

    @Environment(GitHubModel.self) private var gitHub

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.md) {
                IconButton("Back to Pull Requests", systemImage: "chevron.left") { gitHub.closePullRequestPage() }
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + DS.Space.xs }
                Text(page.title)
                    .font(.dsTitle3)
                    .foregroundStyle(.dsTextPrimary)
                    .lineLimit(2)
                    .textSelection(.enabled)
                Text("#\(page.reference.number)")
                    .font(.dsTitle3)
                    .foregroundStyle(.dsTextTertiary)
                Spacer(minLength: DS.Space.lg)
                actions
            }
            ViewThatFits(in: .horizontal) {
                PullRequestPageStatusLine(page: page, compact: false)
                PullRequestPageStatusLine(page: page, compact: true)
                ScrollView(.horizontal, showsIndicators: false) {
                    PullRequestPageStatusLine(page: page, compact: true)
                }
            }
            .padding(.leading, DS.Size.controlXS + DS.Space.md)
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.top, DS.Space.md)
        .padding(.bottom, DS.Space.sm)
    }

    private var actions: some View {
        HStack(spacing: DS.Space.sm) {
            if model.isLoading {
                DotGridLoader(pattern: .waiting)
                    .foregroundStyle(.dsTextSecondary)
                    .frame(width: DS.Size.navIcon, height: DS.Size.navIcon)
                    .frame(width: DS.Size.controlXS, height: DS.Size.controlXS)
                    .accessibilityLabel("Refreshing")
            } else {
                IconButton("Refresh", systemImage: "arrow.clockwise") { Task { await model.load() } }
            }
            IconButton("Open on GitHub", systemImage: "arrow.up.right") { gitHub.openExternally(page.url) }
            if page.isOpen {
                Button {
                    model.isReviewSheetPresented = true
                } label: {
                    Label(reviewTitle, systemImage: "text.bubble")
                }
                .buttonStyle(.ds(model.pendingCommentCount > 0 ? .primary : .secondary))
                .help("Comment on, approve or request changes to this pull request")
                if page.viewerCanMerge {
                    Button("Merge", systemImage: "arrow.triangle.merge") { model.isMergeSheetPresented = true }
                        .buttonStyle(.ds(.secondary))
                        .disabled(page.isDraft)
                        .help(page.isDraft ? "Drafts can't be merged; mark it ready for review on GitHub" : "Merge this pull request")
                }
            }
        }
        .fixedSize()
    }

    private var reviewTitle: String {
        let pending = model.pendingCommentCount
        return pending > 0 ? "Finish Review (\(pending))" : "Review"
    }
}
