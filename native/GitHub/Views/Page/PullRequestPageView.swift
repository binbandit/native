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
        .task(id: model.reference) { await model.loadIfStale() }
        .undoToast($model.undo)
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
