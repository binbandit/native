import GitHub
import SwiftUI

/// The user's open pull requests across GitHub, shown in the detail pane from the sidebar's "Pull
/// Requests" item (⌘⇧P). Grouped by involvement or repository, filterable, refreshed on its own.
struct PullRequestsView: View {
    @Environment(GitHubModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var width: CGFloat = 0

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            PullRequestsHeader(sideInset: sideInset)
            SeparatorLine()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.dsBackground)
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            width = $0
        }
        .onAppear { model.isWatching = true }
        .onDisappear { model.isWatching = false }
        .task { await model.refreshIfDue() }
        .confirmationDialog(
            openAsTaskTitle,
            isPresented: Binding(
                get: { model.openAsTaskCandidate != nil }, set: { if !$0 { model.openAsTaskCandidate = nil } }),
            titleVisibility: .visible
        ) {
            Button("Check Out in New Worktree") {
                Task { await model.confirmOpenAsTask() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Native checks the pull request's branch out into a new worktree and starts a task there. Your current checkout isn't touched."
            )
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(get: { model.actionError != nil }, set: { if !$0 { model.actionError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.actionError ?? "")
        }
    }

    @ViewBuilder private var content: some View {
        switch model.availability {
        case .notInstalled:
            GitHubSetupView(problem: .notInstalled)
        case .notAuthenticated:
            GitHubSetupView(problem: .notAuthenticated)
        default:
            if let inbox = model.inbox {
                list(inbox)
            } else if let error = model.lastError, !model.isRefreshing {
                GitHubSetupView(problem: .failed(error))
            } else {
                PullRequestListSkeleton()
            }
        }
    }

    private func list(_ inbox: PullRequestInbox) -> some View {
        let groups = model.filter.groups(in: inbox)
        return ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xxl) {
                if let error = model.lastError {
                    PullRequestsStaleBanner(error: error, fetchedAt: inbox.fetchedAt)
                }
                if inbox.all.isEmpty {
                    EmptyStateView(
                        "No Open Pull Requests",
                        systemImage: "arrow.triangle.pull",
                        message:
                            "Pull requests you open, are asked to review, or are assigned show up here, from every repository you can see. Open one from a task's branch with Create Pull Request."
                    ) {
                        Button("Open GitHub") {
                            if let url = URL(string: "https://github.com/pulls") { openURL(url) }
                        }
                        .buttonStyle(.ds(.secondary, size: .medium))
                    }
                    .frame(minHeight: PullRequestsLayout.emptyHeight)
                } else if groups.allSatisfy(\.pullRequests.isEmpty),
                    model.filter.isNarrowing || model.filter.grouping == .repository
                {
                    EmptyStateView(
                        "No Matching Pull Requests", systemImage: "line.3.horizontal.decrease",
                        message: filterExplanation
                    ) {
                        Button("Clear Filters") {
                            model.filter.query = ""
                            model.filter.includesDrafts = true
                            model.filter.scope = .all
                        }
                        .buttonStyle(.ds(.secondary, size: .medium))
                    }
                    .frame(minHeight: PullRequestsLayout.emptyHeight)
                } else {
                    ForEach(groups) { group in
                        PullRequestGroupSection(
                            group: group, isCollapsed: collapsed(group.id),
                            showsRepository: model.filter.grouping != .repository)
                    }
                }
            }
            .padding(.leading, sideInset)
            .padding(.trailing, sideInset)
            .padding(.vertical, DS.Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
    }

    /// Centers a column no wider than `contentWidth`, measured on the whole pane rather than inside
    /// the scroll view, so a legacy scroll bar can't shift the list against the header.
    private var sideInset: CGFloat {
        max((width - PullRequestsLayout.contentWidth) / 2, 0) + DS.Space.xl
    }

    private func collapsed(_ id: PullRequestGroup.ID) -> Binding<Bool> {
        Binding(
            get: { model.collapsedGroups.contains(id) },
            set: { isCollapsed in
                if isCollapsed { model.collapsedGroups.insert(id) } else { model.collapsedGroups.remove(id) }
            }
        )
    }

    private var filterExplanation: String {
        let query = model.filter.query.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            return "Nothing matches \u{201C}\(query)\u{201D} in its title, number, branch, author or labels."
        }
        return model.filter.includesDrafts
            ? "Nothing here with these filters." : "Only drafts are left, and drafts are hidden."
    }

    private var openAsTaskTitle: String {
        model.openAsTaskCandidate.map { "Open \($0.reference) as a task?" } ?? ""
    }
}

/// Layout shared by the list's header and content, so their edges line up.
enum PullRequestsLayout {
    /// the reference app's chat column (`CHAT_CONTENT_MAX_WIDTH`), which its pull request inbox reuses.
    static let contentWidth: CGFloat = 760
    static let emptyHeight: CGFloat = 320
}
