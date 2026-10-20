import GitHub
import SwiftUI

/// A comment as GitHub shows one: who and when on a
/// header row, then the body as Markdown, suggestions included.
struct PullRequestCommentCard<Accessory: View>: View {
    let author: String?
    let date: Date?
    let bodyText: String
    let url: URL?
    let edited: Bool
    var emptyText = "No description provided."
    var badge: (label: String, tone: Badge.Tone)?
    let accessory: Accessory

    @Environment(GitHubModel.self) private var gitHub

    init(
        author: String?, date: Date?, body: String, url: URL?, edited: Bool,
        emptyText: String = "No description provided.",
        badge: (label: String, tone: Badge.Tone)? = nil, @ViewBuilder accessory: () -> Accessory
    ) {
        self.author = author
        self.date = date
        self.bodyText = body
        self.url = url
        self.edited = edited
        self.emptyText = emptyText
        self.badge = badge
        self.accessory = accessory()
    }

    var body: some View {
        Card(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                header
                SeparatorLine()
                Group {
                    if bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(emptyText)
                            .font(.dsBody)
                            .foregroundStyle(.dsTextTertiary)
                    } else {
                        PullRequestMarkdownBody(source: bodyText)
                    }
                }
                .padding(DS.Space.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var header: some View {
        HStack(spacing: DS.Space.sm) {
            GitHubAuthorAvatar(login: author)
            Text(author ?? "ghost")
                .font(.dsBodyMedium)
                .foregroundStyle(.dsTextPrimary)
            if let date {
                Text(DSFormat.compactAge(date, now: .now) + (edited ? " · edited" : ""))
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextTertiary)
                    .help(date.formatted(date: .abbreviated, time: .shortened))
            }
            if let badge {
                Badge(badge.label, tone: badge.tone, style: .soft)
            }
            Spacer(minLength: DS.Space.md)
            accessory
            if let url {
                Menu {
                    Button("Open on GitHub", systemImage: "arrow.up.right") { gitHub.openExternally(url) }
                    Button("Copy Link", systemImage: "link") { gitHub.copy(url.absoluteString) }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: DS.Size.controlXS, height: DS.Size.controlXS)
                        .contentShape(.rect)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .foregroundStyle(.dsTextSecondary)
                .accessibilityLabel("Comment Options")
            }
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.vertical, DS.Space.sm)
    }
}

extension PullRequestCommentCard where Accessory == EmptyView {
    init(
        author: String?, date: Date?, body: String, url: URL?, edited: Bool,
        emptyText: String = "No description provided.",
        badge: (label: String, tone: Badge.Tone)? = nil
    ) {
        self.init(author: author, date: date, body: body, url: url, edited: edited, emptyText: emptyText, badge: badge)
        {
            EmptyView()
        }
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Comment cards") {
    DSPreviewPair {
        VStack(spacing: DS.Space.lg) {
            PullRequestCommentCard(
                author: "preview-reviewer", date: .now.addingTimeInterval(-3 * 3600),
                body: "Reads well. Two questions inline, mostly about what happens when the agent **can't steer**.",
                url: URL(string: "https://github.com/binbandit/native/pull/212"), edited: true,
                badge: (label: "Commented", tone: .neutral))
            // A pull request opened without a description.
            PullRequestCommentCard(
                author: "binbandit", date: .now.addingTimeInterval(-26 * 3600), body: "", url: nil, edited: false)
        }
        .frame(width: PullRequestsLayout.contentWidth)
    }
    .environment(GitHubModel.preview())
}
#endif
