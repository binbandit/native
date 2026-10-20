import GitHub
import SwiftUI

/// Choosing the pull request to open as a task, from the command palette: the user's open pull
/// requests (authored, to review, assigned), filtered as they type, or any pull request by its link
/// or `owner/name#123`. Return opens the first match.
struct PullRequestTaskPicker: View {
    let opener: PullRequestTaskOpener

    @Environment(GitHubModel.self) private var gitHub
    @State private var query = ""
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        let typed = Self.reference(in: query)
        let matches = pullRequests
        VStack(spacing: 0) {
            SearchField(
                "Search your pull requests, or paste a link", text: $query,
                prompt: Text("Search your pull requests, or paste a link").foregroundStyle(.dsTextTertiary)
            )
            .focused($isSearchFocused)
            .onSubmit {
                if let typed {
                    opener.open(typed)
                } else if let first = matches.first {
                    opener.open(first)
                }
            }
            .padding(DS.Space.lg)
            SeparatorLine()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let typed {
                        row(title: "Open \(typed.display)", subtitle: typed.url.absoluteString, state: nil) {
                            opener.open(typed)
                        }
                    }
                    ForEach(matches) { pullRequest in
                        row(
                            title: pullRequest.title,
                            subtitle: [pullRequest.reference, pullRequest.headRefName].compactMap(\.self)
                                .joined(separator: " · "),
                            state: pullRequest
                        ) {
                            opener.open(pullRequest)
                        }
                    }
                    if typed == nil, matches.isEmpty {
                        empty
                    }
                }
                .padding(DS.Space.sm)
            }
            .frame(height: PullRequestTaskSheetLayout.pickerHeight)
        }
        .onAppear { isSearchFocused = true }
        .task { await gitHub.refreshIfDue() }
    }

    private var pullRequests: [PullRequestSummary] {
        let all = (gitHub.inbox?.all ?? []).filter { $0.state == .open }
        let words = query.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return all }
        return all.filter { pullRequest in
            let haystack = [
                pullRequest.title, pullRequest.reference, pullRequest.headRefName, pullRequest.author?.login,
            ]
            .compactMap(\.self).joined(separator: " ").lowercased()
            return words.allSatisfy(haystack.contains)
        }
    }

    private func row(
        title: String, subtitle: String, state: PullRequestSummary?, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: DS.Space.md) {
                Group {
                    if let state {
                        PullRequestStateIcon(state: state.state, isDraft: state.isDraft)
                    } else {
                        Image(systemName: "link")
                            .font(.system(size: DS.Size.navIcon))
                            .foregroundStyle(.dsTextSecondary)
                    }
                }
                .frame(width: DS.Size.rowLeading, height: DS.Size.rowLeading)
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(title)
                        .font(.dsBody)
                        .foregroundStyle(.dsTextPrimary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.dsCaption)
                        .foregroundStyle(.dsTextTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Space.md)
            .padding(.vertical, DS.Space.sm)
            .contentShape(.rect)
        }
        .buttonStyle(PullRequestTaskPickerRowStyle())
    }

    @ViewBuilder private var empty: some View {
        if gitHub.inbox == nil, gitHub.lastError == nil {
            HStack(spacing: DS.Space.sm) {
                DotGridLoader(pattern: .waiting)
                    .foregroundStyle(.dsTextSecondary)
                    .frame(width: DS.Size.navIcon, height: DS.Size.navIcon)
                Text("Loading your pull requests…")
                    .font(.dsBody)
                    .foregroundStyle(.dsTextSecondary)
            }
            .padding(DS.Space.lg)
        } else {
            EmptyStateView(
                query.isEmpty ? "No Open Pull Requests" : "No Matching Pull Requests",
                systemImage: "arrow.triangle.pull",
                message: emptyMessage)
        }
    }

    private var emptyMessage: String {
        if let error = gitHub.lastError, gitHub.inbox == nil {
            return "\(error.localizedDescription) Paste a pull request's link to open it anyway."
        }
        return query.isEmpty
            ? "Pull requests you open, review or are assigned show up here. Paste any pull request's link to open it."
            : "Nothing of yours matches “\(query)”. Paste a pull request's link, or owner/name#123, to open any other."
    }

    /// A pull request the text names: its link, or `owner/name#123`.
    static func reference(in text: String) -> PullRequestReference? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: text), url.scheme?.hasPrefix("http") == true {
            return PullRequestReference(url: url)
        }
        let parts = text.split(separator: "#")
        guard parts.count == 2, let number = Int(parts[1]),
            let repository = RemoteRepository(nameWithOwner: String(parts[0]))
        else { return nil }
        return PullRequestReference(owner: repository.owner, name: repository.name, number: number)
    }
}

/// A list row that highlights under the pointer and while pressed.
private struct PullRequestTaskPickerRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PickerRow(configuration: configuration)
    }

    private struct PickerRow: View {
        let configuration: Configuration
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .background {
                    RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
                        .fill(configuration.isPressed || isHovered ? .dsHover : .clear)
                }
                .trackHover($isHovered)
        }
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Pick a pull request") {
    let app = AppModel.preview()
    DSPreviewPair {
        PullRequestTaskPicker(opener: PullRequestTaskPreviewFixtures.opener(app))
            .frame(width: PullRequestTaskSheetLayout.width, height: 420)
    }
    .environment(GitHubModel.preview(inbox: PullRequestPreviewFixtures.inbox))
}

#Preview("Pick a pull request - None open") {
    let app = AppModel.preview()
    DSPreviewPair {
        PullRequestTaskPicker(opener: PullRequestTaskPreviewFixtures.opener(app))
            .frame(width: PullRequestTaskSheetLayout.width, height: 320)
    }
    .environment(
        GitHubModel.preview(inbox: PullRequestInbox(authored: [], reviewRequested: [], assigned: [], fetchedAt: .now)))
}
#endif
