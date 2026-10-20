import SwiftUI

extension View {
    /// Presents the pull request page's merge sheet whenever `GitHubModel.requestMerge(_:)` is
    /// called: from a row of the list or a task's pull request card, wherever the window is. Attach
    /// once, near the root of the window.
    func pullRequestMergeSheet(_ model: GitHubModel) -> some View {
        sheet(isPresented: Binding(get: { model.mergeRequest != nil }, set: { if !$0 { model.mergeRequest = nil } })) {
            if let reference = model.mergeRequest {
                MergePullRequestSheet(model: model.pageModel(for: reference))
                    .environment(model)
            }
        }
    }
}
