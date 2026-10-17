import Git
import SwiftUI

/// A task's uncommitted changes, for the window's inspector column (the reference app's Changes panel):
/// branch and next action on top, the changed files grouped by area, and the selected file's diff
/// below. Stays current on its own; `GitStore.refresh(folder:)` forces a rescan.
struct GitChangesInspector: View {
    let model: GitRepositoryModel
    /// Opens the GitHub feature's pull request flow; the button is hidden without it.
    var onCreatePullRequest: (() -> Void)?

    @State private var isCommitting = false
    @State private var pendingDiscard: [FileChange] = []

    var body: some View {
        VStack(spacing: 0) {
            switch model.state {
            case .loading:
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .notRepository:
                EmptyStateView("Not a Git repository", systemImage: "folder", message: model.folder.path(percentEncoded: false))
            case .failed(let message):
                EmptyStateView("Couldn't read the repository", systemImage: "exclamationmark.triangle", message: message) {
                    Button("Try Again") { model.refresh() }
                        .buttonStyle(.ds(.secondary))
                }
            case .ready:
                ready
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.dsBackground)
        .alert(discardTitle, isPresented: isConfirmingDiscard) {
            Button("Discard", role: .destructive) {
                let changes = pendingDiscard
                Task { await model.discard(changes) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The current files move to the Trash.")
        }
    }

    @ViewBuilder private var ready: some View {
        GitChangesHeader(model: model, isCommitting: $isCommitting, onCreatePullRequest: onCreatePullRequest)
        SeparatorLine()
        if let error = model.actionError {
            errorBanner(error)
        }
        if let status = model.status, !status.isClean {
            summary(status)
            SeparatorLine()
            // The list takes what it needs, up to a share of the column, and the diff the rest.
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    GitChangeList(model: model) { pendingDiscard = $0 }
                        .frame(height: min(GitChangeList.contentHeight(for: status), max(proxy.size.height * GitMetrics.listShare, GitMetrics.listMinHeight)))
                    SeparatorLine()
                    GitDiffPane(change: model.selectedChange, content: model.selectedDiff)
                }
            }
        } else {
            EmptyStateView("No changes", systemImage: "checkmark.circle", message: cleanMessage)
        }
    }

    private func summary(_ status: RepositoryStatus) -> some View {
        HStack(spacing: DS.Space.sm) {
            Text(status.changedFileCount == 1 ? "1 file changed" : "\(status.changedFileCount) files changed")
                .font(.dsBodyMedium)
                .foregroundStyle(.dsTextSecondary)
            Spacer(minLength: DS.Space.md)
            DiffStatLabel(added: status.totals.additions, removed: status.totals.deletions)
        }
        .padding(.horizontal, DS.Space.lg)
        .frame(height: GitMetrics.summaryHeight)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: DS.Space.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.dsDanger)
            Text(message)
                .font(.dsBody)
                .foregroundStyle(.dsTextPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            IconButton("Dismiss", systemImage: "xmark") { model.actionError = nil }
        }
        .padding(DS.Space.md)
        .background(.dsDanger.opacity(0.08))
    }

    private var cleanMessage: String {
        guard let branch = model.branch else { return "" }
        if branch.ahead > 0 {
            return branch.ahead == 1 ? "1 commit to push." : "\(branch.ahead) commits to push."
        }
        return "The working tree matches the last commit on \(branch.displayName)."
    }

    private var isConfirmingDiscard: Binding<Bool> {
        Binding(get: { !pendingDiscard.isEmpty }, set: { if !$0 { pendingDiscard = [] } })
    }

    private var discardTitle: String {
        let paths = Set(pendingDiscard.map(\.path))
        if paths.count == 1, let change = pendingDiscard.first {
            return "Discard changes to \(change.fileName)?"
        }
        return "Discard changes to \(paths.count) files?"
    }
}
