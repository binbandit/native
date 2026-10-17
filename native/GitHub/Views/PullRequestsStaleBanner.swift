import GitHub
import SwiftUI

/// Above a list that couldn't refresh: why, and how old what's shown is.
struct PullRequestsStaleBanner: View {
    let error: GitHubError
    let fetchedAt: Date

    @Environment(GitHubModel.self) private var model

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
        HStack(spacing: DS.Space.md) {
            Image(systemName: systemImage)
                .font(.system(size: DS.Size.navIcon))
                .foregroundStyle(.dsWarning)
            TimelineView(.everyMinute) { _ in
                Text("\(reason) Showing results from \(fetchedAt, format: .relative(presentation: .named)).")
                    .font(.dsBody)
                    .foregroundStyle(.dsTextSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: DS.Space.md)
            Button("Retry") {
                Task { await model.refresh() }
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
