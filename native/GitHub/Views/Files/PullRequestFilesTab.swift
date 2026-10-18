import GitHub
import SwiftUI

/// Every changed file's diff, with a file tree beside them when there's room. Viewed and
/// generated files start folded; diffs load as the list reaches them.
struct PullRequestFilesTab: View {
    let model: PullRequestPageModel
    let page: PullRequestPage

    @State private var width: CGFloat = 0
    @State private var showsTree = true

    private var hasRoomForTree: Bool {
        width >= PullRequestFilesLayout.treeWidth * 3
    }

    var body: some View {
        VStack(spacing: 0) {
            PullRequestFilesBar(model: model, showsTree: $showsTree, canShowTree: hasRoomForTree)
            SeparatorLine()
            HStack(spacing: 0) {
                if showsTree, hasRoomForTree {
                    PullRequestFileTree(model: model)
                        .frame(width: PullRequestFilesLayout.treeWidth)
                    SeparatorLine(axis: .vertical)
                }
                diffs
            }
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            width = $0
        }
        .task(id: page.headRefOid) {
            if model.patchPagesLoaded == 0 { await model.loadNextPatchPage() }
            await model.loadAllFiles()
        }
    }

    private var diffs: some View {
        PullRequestFilesList(model: model)
            .codeTextStyle(.compact)
    }
}

enum PullRequestFilesLayout {
    static let treeWidth: CGFloat = 248
}
