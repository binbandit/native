import SwiftUI

extension View {
    /// Presents the Create Pull Request sheet whenever `GitHubModel.presentCreatePullRequest(_:)`
    /// is called. Attach once, near the root of the window.
    func createPullRequestSheet(_ model: GitHubModel) -> some View {
        @Bindable var model = model
        return sheet(item: $model.createRequest) { request in
            CreatePullRequestSheet(request: request)
                .environment(model)
        }
    }
}
