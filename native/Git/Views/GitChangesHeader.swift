import Git
import SwiftUI

/// The inspector's top row: the branch, a refresh button and the next sensible action: commit
/// when there are changes, push when there are commits to push, otherwise a pull request.
struct GitChangesHeader: View {
    let model: GitRepositoryModel
    @Binding var isCommitting: Bool
    var fileMenu: AnyView? = nil
    @Environment(\.gitChangesClose) private var close
    @State private var isSmartCommitting = false
    let onCreatePullRequest: (() -> Void)?

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            if let fileMenu {
                fileMenu
            } else if let branch = model.branch {
                GitBranchBadge(branch: branch, font: .dsBodyMedium)
            }
            Spacer(minLength: DS.Space.md)
            if model.isWorking {
                DotGridLoader(pattern: .typing)
                    .foregroundStyle(.dsTextSecondary)
                    .frame(width: GitMetrics.loaderSmall, height: GitMetrics.loaderSmall)
                    .help("Working…")
            }
            if fileMenu == nil {
                IconButton("Refresh", systemImage: "arrow.clockwise") {
                    Task { await model.refreshNow() }
                }
                .dsHitTarget(DS.Size.controlXS)
            }
            primaryAction
            if let close {
                // The key it teaches is also the button, so touch has the same way back. As a cancel
                // shortcut it answers Escape wherever focus is, like the overlay it replaces.
                Button(action: close.close) { Kbd("esc", compact: true) }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    .dsHitTarget(DS.Size.controlXS)
                    .accessibilityLabel("Close Changes")
                    .help("Return to the conversation (Escape)")
            }
        }
        .padding(.horizontal, DS.Space.md)
        .frame(height: fileMenu == nil ? GitMetrics.headerHeight : DS.TaskWell.changesHeaderHeight)
    }

    @ViewBuilder private var primaryAction: some View {
        if let status = model.status, let branch = model.branch {
            if fileMenu == nil, status.changedFileCount > 1, status.conflicted.isEmpty {
                IconButton("Smart Commit…", systemImage: "square.stack.3d.up") { isSmartCommitting = true }
                    .dsHitTarget(DS.Size.controlXS)
                    .sheet(isPresented: $isSmartCommitting) {
                        GitSmartCommitSheet(repository: model)
                    }
            }
            if !status.isClean {
                Button("Commit", systemImage: "checkmark") { isCommitting = true }
                    .buttonStyle(.ds(.primary))
                    .disabled(!status.conflicted.isEmpty)
                    .help(status.conflicted.isEmpty ? "Commit changes" : "Resolve and stage the conflicted files first")
                    .popover(isPresented: $isCommitting, arrowEdge: .bottom) {
                        GitCommitPopover(
                            model: model, isPresented: $isCommitting, onCreatePullRequest: onCreatePullRequest)
                    }
            } else if fileMenu == nil, model.canPush {
                Button(branch.upstream == nil ? "Publish" : "Push \(branch.ahead)", systemImage: "arrow.up") {
                    Task { await model.push() }
                }
                .buttonStyle(.ds(.secondary))
                .help(
                    branch.upstream == nil
                        ? "Push the branch and track it" : "Push commits to \(branch.upstream ?? "the upstream")")
            } else if fileMenu == nil, let onCreatePullRequest, model.canCreatePullRequest {
                Button("Create PR", systemImage: "arrow.triangle.pull", action: onCreatePullRequest)
                    .buttonStyle(.ds(.secondary))
            }
        }
    }
}

#if DEBUG
#Preview("Changes header") {
    DSPreviewPair {
        VStack(spacing: DS.Space.lg) {
            GitChangesHeader(model: GitPreviewFixtures.model, isCommitting: .constant(false), onCreatePullRequest: {})
            GitChangesHeader(
                model: GitPreviewFixtures.cleanModel, isCommitting: .constant(false), onCreatePullRequest: nil)
        }
        .frame(width: GitMetrics.inspectorIdealWidth)
    }
}
#endif
