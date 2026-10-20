import GitHub
import SwiftUI

/// Above the diffs: how far the review has got (files viewed), and a note when the pull request is
/// big enough that diffs load as you scroll.
struct PullRequestFilesBar: View {
    let model: PullRequestPageModel
    @Binding var showsTree: Bool
    let canShowTree: Bool

    var body: some View {
        HStack(spacing: DS.Space.md) {
            if canShowTree {
                IconButton(
                    showsTree ? "Hide File Tree" : "Show File Tree", systemImage: "sidebar.left", isActive: showsTree
                ) {
                    withAnimation(.dsPanel) { showsTree.toggle() }
                }
            }
            ProgressView(value: Double(model.viewedCount), total: Double(max(model.totalFiles, 1)))
                .progressViewStyle(.linear)
                .tint(.dsSuccess)
                .frame(width: DS.Size.sidebarWidth / 3)
                .accessibilityHidden(true)
            Text("\(model.viewedCount) of \(model.totalFiles) files viewed")
                .font(.dsCaption)
                .foregroundStyle(.dsTextSecondary)
            if model.totalFiles > 100 {
                Text("Large pull request: diffs load as you scroll.")
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextTertiary)
            }
            Spacer(minLength: DS.Space.md)
            if model.isLoadingPatches {
                DotGridLoader(pattern: .waiting)
                    .foregroundStyle(.dsTextTertiary)
                    .frame(width: DS.Size.navIcon, height: DS.Size.navIcon)
                    .accessibilityLabel("Loading diffs")
            }
            if let pending = pendingNote {
                Text(pending)
                    .font(.dsCaption)
                    .foregroundStyle(.dsAttention)
            }
        }
        .padding(.horizontal, DS.Space.lg)
        .frame(height: DS.Size.controlMD)
    }

    private var pendingNote: String? {
        let count = model.pendingCommentCount
        return count > 0 ? "\(count) pending comment\(count == 1 ? "" : "s") in your review" : nil
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Files bar") {
    DSPreviewPair {
        VStack(spacing: DS.Space.lg) {
            PullRequestPagePreview { model, _ in
                PullRequestFilesBar(model: model, showsTree: .constant(true), canShowTree: true)
            }
            // Too narrow for the tree, so its toggle goes.
            PullRequestPagePreview { model, _ in
                PullRequestFilesBar(model: model, showsTree: .constant(false), canShowTree: false)
            }
            .frame(width: 420)
        }
        .frame(width: 900)
    }
}
#endif
