import Git
import SwiftUI

/// The inspector's top row: the branch, a refresh button and the next sensible action: commit
/// when there are changes, push when there are commits to push, otherwise a pull request.
struct GitChangesHeader: View {
    let model: GitRepositoryModel
    @Binding var isCommitting: Bool
    let onCreatePullRequest: (() -> Void)?

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            if let branch = model.branch {
                GitBranchBadge(branch: branch, font: .dsBodyMedium)
            }
            Spacer(minLength: DS.Space.md)
            if model.isWorking {
                DotGridLoader(pattern: .typing)
                    .foregroundStyle(.dsTextSecondary)
                    .frame(width: GitMetrics.loaderSmall, height: GitMetrics.loaderSmall)
                    .help("Working…")
            }
            IconButton("Refresh", systemImage: "arrow.clockwise") {
                Task { await model.refreshNow() }
            }
            primaryAction
        }
        .padding(.horizontal, DS.Space.md)
        .frame(height: GitMetrics.headerHeight)
    }

    @ViewBuilder private var primaryAction: some View {
        if let status = model.status, let branch = model.branch {
            if !status.isClean {
                Button("Commit", systemImage: "checkmark") { isCommitting = true }
                    .buttonStyle(.ds(.primary))
                    .help("Commit changes")
                    .popover(isPresented: $isCommitting, arrowEdge: .bottom) {
                        GitCommitPopover(model: model, isPresented: $isCommitting, onCreatePullRequest: onCreatePullRequest)
                    }
            } else if branch.ahead > 0 || (branch.upstream == nil && !branch.isDetached && !branch.isUnborn) {
                Button(branch.upstream == nil ? "Publish" : "Push \(branch.ahead)", systemImage: "arrow.up") {
                    Task { await model.push() }
                }
                .buttonStyle(.ds(.secondary))
                .help(branch.upstream == nil ? "Push the branch and track it" : "Push commits to \(branch.upstream ?? "the upstream")")
            } else if let onCreatePullRequest, !branch.isDetached {
                Button("Create PR", systemImage: "arrow.triangle.pull", action: onCreatePullRequest)
                    .buttonStyle(.ds(.secondary))
            }
        }
    }
}
