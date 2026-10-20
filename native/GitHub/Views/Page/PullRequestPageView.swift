import GitHub
import SwiftUI

/// A pull request in Native: its header, then Conversation, Files Changed and Checks. Shown in the
/// Pull Requests pane when the user opens one (from the list, a task's badge or a link) and the
/// setting says to open pull requests in Native.
struct PullRequestPageView: View {
    let model: PullRequestPageModel

    @Environment(GitHubModel.self) private var gitHub

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            if let page = model.page {
                PullRequestPageHeader(model: model, page: page)
                PullRequestPageTabBar(model: model, page: page)
                SeparatorLine()
                if let error = model.actionError {
                    actionErrorBanner(error)
                } else if let error = model.loadError, let loadedAt = model.loadedAt {
                    PullRequestsStaleBanner(error: error, fetchedAt: loadedAt) { await model.load() }
                        .padding(.horizontal, DS.Space.xl)
                        .padding(.top, DS.Space.md)
                }
                content(page)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = model.loadError {
                PullRequestPageBackBar(reference: model.reference)
                SeparatorLine()
                PullRequestPageLoadError(model: model, error: error)
            } else {
                PullRequestPageBackBar(reference: model.reference)
                SeparatorLine()
                PullRequestListSkeleton()
            }
        }
        .background(.dsBackground)
        // Fresh on arrival, then once a minute while it's on screen: one GraphQL request each.
        .task(id: model.reference) {
            while !Task.isCancelled {
                await model.loadIfStale()
                try? await Task.sleep(for: .seconds(PullRequestPageModel.freshness))
            }
        }
        // Pull request links in comments open their page here (per the setting); others the browser.
        .environment(
            \.openURL,
            OpenURLAction { url in
                gitHub.open(url)
                return .handled
            }
        )
        .undoToast($model.undo)
        // Private questions about the pull request, beside the page (native/GitHub/Ask).
        .pullRequestAskPanel(for: model.reference)
        .sheet(isPresented: $model.isReviewSheetPresented) {
            SubmitReviewSheet(model: model)
                .environment(gitHub)
        }
        .sheet(isPresented: $model.isMergeSheetPresented) {
            MergePullRequestSheet(model: model)
                .environment(gitHub)
        }
    }

    @ViewBuilder private func content(_ page: PullRequestPage) -> some View {
        switch model.tab {
        case .conversation: PullRequestConversationTab(model: model, page: page)
        case .files: PullRequestFilesTab(model: model, page: page)
        case .checks: PullRequestChecksTab(model: model, page: page)
        }
    }

    private func actionErrorBanner(_ error: GitHubError) -> some View {
        NoticeBanner(
            tone: error.isPermissionProblem ? .warning : .danger,
            title: error.localizedDescription,
            detail: error.recoverySuggestion,
            footnote: error.stderr.flatMap { $0 == error.localizedDescription || $0.isEmpty ? nil : $0 }
        ) {
            Button("Dismiss") { model.actionError = nil }
                .buttonStyle(.ds(.ghost))
        }
        .padding(.horizontal, DS.Space.xl)
        .padding(.top, DS.Space.md)
    }
}

extension GitHubError {
    /// Refusals the user can't retry their way out of.
    var isPermissionProblem: Bool {
        switch self {
        case .permissionDenied, .notAuthenticated: true
        default: false
        }
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Pull request page - Conversation") {
    PullRequestPageViewPreview(scenario: .reviewing, tab: .conversation)
}

#Preview("Pull request page - Files changed") {
    PullRequestPageViewPreview(scenario: .reviewing, tab: .files)
}

#Preview("Pull request page - Checks") {
    PullRequestPageViewPreview(scenario: .reviewing, tab: .checks)
}

#Preview("Pull request page - Own, ready to merge") {
    PullRequestPageViewPreview(scenario: .own, tab: .conversation)
}

#Preview("Pull request page - Merged") {
    PullRequestPageViewPreview(scenario: .merged, tab: .conversation)
}

#Preview("Pull request page - Offline") {
    PullRequestPageViewPreview(scenario: .offline, tab: .conversation)
}

#Preview("Pull request page - Narrow") {
    PullRequestPageViewPreview(scenario: .reviewing, tab: .conversation, width: 440)
}

/// The page as the Pull Requests pane shows it, loading binbandit/native#212 from fixture gh
/// answers on the tab given.
private struct PullRequestPageViewPreview: View {
    @State private var gitHub: GitHubModel
    @State private var model: PullRequestPageModel
    private let width: CGFloat

    init(scenario: PullRequestPreviewRunner.Scenario, tab: PullRequestPageModel.Tab, width: CGFloat = 900) {
        let gitHub = GitHubModel.pagePreview(scenario)
        let model = PullRequestPageModel(reference: PullRequestPreviewRunner.reference, gitHub: gitHub)
        model.tab = tab
        _gitHub = State(initialValue: gitHub)
        _model = State(initialValue: model)
        self.width = width
    }

    var body: some View {
        DSPreviewPair {
            PullRequestPageView(model: model)
                .frame(width: width, height: 760)
        }
        .environment(gitHub)
    }
}
#endif
