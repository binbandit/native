#if NATIVE_PREVIEWS_WIP
import GitHub
import SwiftUI

/// Loads binbandit/native#212 through the app's own page model from fixture gh answers
/// (`PullRequestPreviewRunner`), then shows `content` with it; the loader while it loads. For
/// previews of the pieces of a pull request page, which take its model and the loaded page.
struct PullRequestPagePreview<Content: View>: View {
    var scenario: PullRequestPreviewRunner.Scenario = .reviewing
    /// Also loads the patches and checks, for the Files Changed and Checks tabs.
    var loadsEverything = true
    @ViewBuilder let content: (PullRequestPageModel, PullRequestPage) -> Content

    @State private var gitHub: GitHubModel?
    @State private var model: PullRequestPageModel?

    var body: some View {
        Group {
            if let gitHub, let model, let page = model.page {
                content(model, page)
                    .environment(gitHub)
            } else {
                LoadingStateView("Loading the pull request")
            }
        }
        .task {
            let gitHub = GitHubModel.pagePreview(scenario)
            let model = PullRequestPageModel(reference: PullRequestPreviewRunner.reference, gitHub: gitHub)
            gitHub.pages[model.reference] = model
            await model.load(prefetchingPatches: false)
            if loadsEverything {
                await model.loadNextPatchPage()
                await model.loadChecks()
            }
            self.gitHub = gitHub
            self.model = model
        }
    }
}

extension PullRequestFilesRow {
    /// A row of diff lines, for previews of the blocks alone.
    var isPreviewBlock: Bool {
        if case .block = kind { true } else { false }
    }
}

extension GitHubModel {
    /// A GitHub model whose gh is the fixture runner, so pages load binbandit/native#212.
    static func pagePreview(_ scenario: PullRequestPreviewRunner.Scenario = .reviewing) -> GitHubModel {
        GitHubModel(environment: { _ in [:] }, runner: PullRequestPreviewRunner(scenario: scenario))
    }
}
#endif
