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
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DS.Space.lg) {
                    if let error = model.patchError {
                        NoticeBanner(
                            tone: .warning, title: "Some diffs couldn't load", detail: error.localizedDescription
                        ) {
                            Button("Try Again") { Task { await model.loadNextPatchPage() } }
                                .buttonStyle(.ds(.secondary))
                        }
                    }
                    ForEach(model.files) { file in
                        PullRequestFileSection(model: model, file: file)
                            .id(file.path)
                    }
                    if model.filesCursor != nil {
                        Text("Loading the rest of the \(model.totalFiles) files…")
                            .font(.dsBody)
                            .foregroundStyle(.dsTextTertiary)
                    }
                }
                .padding(DS.Space.lg)
            }
            .scrollContentBackground(.hidden)
            .onChange(of: model.focusedFile) { _, path in
                guard let path else { return }
                withAnimation(.dsStandard) { proxy.scrollTo(path, anchor: .top) }
                model.focusedFile = nil
            }
        }
    }
}

enum PullRequestFilesLayout {
    static let treeWidth: CGFloat = 248
    /// Past this many lines a file shows the start and a button for the rest.
    static let initialLineLimit = 400
}
