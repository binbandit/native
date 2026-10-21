import GitHub
import SwiftUI

/// Above a list that couldn't refresh: why, and how old what's shown is.
struct PullRequestsStaleBanner: View {
    let error: GitHubError
    let fetchedAt: Date
    /// What Retry does; refreshing the list unless given.
    var retry: (() async -> Void)?

    @Environment(GitHubModel.self) private var model

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
        HStack(spacing: DS.Space.md) {
            Image(systemName: systemImage)
                .font(.system(size: DS.Size.navIcon))
                .foregroundStyle(.dsWarning)
            DSMinuteTimeline { _ in
                Text("\(reason) Showing results from \(fetchedAt.formatted(.relative(presentation: .named))).")
                    .font(.dsBody)
                    .foregroundStyle(.dsTextSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: DS.Space.md)
            Button("Retry") {
                Task {
                    if let retry { await retry() } else { await model.refresh() }
                }
            }
            .buttonStyle(.ds(.ghost))
            .disabled(model.isRefreshing)
        }
        .padding(.leading, DS.Space.lg)
        .padding(.trailing, DS.Space.xs)
        .padding(.vertical, DS.Space.xs)
        .background(.dsSurfaceSunken, in: shape)
        .overlay { shape.strokeBorder(.dsSeparator, lineWidth: 1) }
    }

    private var systemImage: String {
        if case .offline = error { "wifi.slash" } else { "exclamationmark.triangle" }
    }

    private var reason: String {
        switch error {
        case .offline: "GitHub can't be reached."
        case .rateLimited: "GitHub's rate limit was reached."
        case .timedOut: "GitHub CLI took too long to respond."
        default: "Pull requests couldn't refresh."
        }
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Stale list") {
    DSPreviewPair {
        VStack(spacing: DS.Space.lg) {
            PullRequestsStaleBanner(
                error: .offline("error connecting to api.github.com"), fetchedAt: .now.addingTimeInterval(-25 * 60))
            PullRequestsStaleBanner(
                error: .rateLimited("API rate limit exceeded for user"), fetchedAt: .now.addingTimeInterval(-3 * 3600))
        }
        .frame(width: PullRequestsLayout.contentWidth)
    }
    .environment(GitHubModel.preview(inbox: PullRequestPreviewFixtures.inbox))
}
#endif
