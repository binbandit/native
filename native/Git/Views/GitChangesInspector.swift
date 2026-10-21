import Git
import SwiftUI

/// A task's changes, for the window's inspector column: branch and next action on top, then the
/// scope (the latest turn's changes, the uncommitted ones, or the branch's), the changed files and
/// the selected file's diff below. Stays current on its own; `GitStore.refresh(folder:)` forces a
/// rescan.
struct GitChangesInspector: View {
    let model: GitRepositoryModel
    /// Which changes to show; without it, only the uncommitted ones.
    var review: GitChangesReview?
    /// The task, whose latest turn This Turn shows.
    var session: SessionModel?
    /// Adaptive hosts move the pane between containers without ending the review.
    var resetsReviewOnDisappear = true
    /// Opens the GitHub feature's pull request flow; the button is hidden without it.
    var onCreatePullRequest: (() -> Void)?

    @State private var isCommitting = false
    @State private var pendingDiscard: [FileChange] = []

    var body: some View {
        VStack(spacing: 0) {
            switch model.state {
            case .loading:
                DotGridLoader(pattern: .settingUp)
                    .foregroundStyle(.dsTextTertiary)
                    .frame(width: GitMetrics.loaderLarge, height: GitMetrics.loaderLarge)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .notRepository:
                noticeBanner
                EmptyStateView(
                    "Not a Git repository",
                    systemImage: "folder",
                    message:
                        "\(model.folder.lastPathComponent) isn't tracked by git yet. Create a repository to review and commit changes here."
                ) {
                    Button("Create Repository") { Task { await model.initializeRepository() } }
                        .buttonStyle(.ds(.secondary))
                }
            case .failed(let message):
                EmptyStateView(
                    "Couldn't read the repository", systemImage: "exclamationmark.triangle", message: message
                ) {
                    Button("Try Again") { model.refresh() }
                        .buttonStyle(.ds(.secondary))
                }
            case .ready:
                ready
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.dsBackground)
        // This Turn follows the latest turn as the agent works.
        .onChange(of: session?.phase) { followLatestTurn() }
        .onChange(of: session?.completedWriteCount) { followLatestTurn() }
        // It opens again on the uncommitted changes (⌘⇧D, docs/keyboard.md).
        .onDisappear { if resetsReviewOnDisappear { review?.reset() } }
        .alert(discardTitle, isPresented: isConfirmingDiscard) {
            Button("Discard", role: .destructive) {
                let changes = pendingDiscard
                Task { await model.discard(changes) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Native saves a checkpoint first, so you can restore them from the notice that follows.")
        }
    }

    @ViewBuilder private var ready: some View {
        GitChangesHeader(model: model, isCommitting: $isCommitting, onCreatePullRequest: onCreatePullRequest)
        SeparatorLine()
        if let review {
            GitChangesScopePicker(scope: scopeBinding(review))
            SeparatorLine()
        }
        noticeBanner
        switch review?.scope ?? .uncommitted {
        case .uncommitted:
            uncommitted
        case .turn:
            if let review, let turn = review.turn {
                GitRangeChangesView(repository: model, review: review, request: .turn(turn))
            } else {
                EmptyStateView(
                    "No turn yet", systemImage: "text.bubble",
                    message: "When the agent finishes a turn, the files it changed show here, committed or not.")
            }
        case .branch:
            if let review {
                GitRangeChangesView(repository: model, review: review, request: .branch)
            }
        }
    }

    @ViewBuilder private var uncommitted: some View {
        if let status = model.status, !status.isClean {
            if !status.conflicted.isEmpty {
                conflictsBanner(count: status.conflicted.count)
            }
            summary(status)
            SeparatorLine()
            // The list takes what it needs, up to a share of the column, and the diff the rest.
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    GitChangeList(model: model, pendingDiscard: $pendingDiscard)
                        .frame(
                            height: min(
                                GitChangeList.contentHeight(for: status),
                                max(proxy.size.height * GitMetrics.listShare, GitMetrics.listMinHeight)))
                    SeparatorLine()
                    // Reads the selection and its diff itself, so a diff arriving redraws only the pane.
                    GitDiffPane(model: model)
                }
            }
        } else {
            EmptyStateView("No changes", systemImage: "checkmark.circle", message: cleanMessage) {
                if let branch = model.branch, model.canPush {
                    Button(branch.upstream == nil ? "Publish Branch" : "Push", systemImage: "arrow.up") {
                        Task { await model.push() }
                    }
                    .buttonStyle(.ds(.secondary))
                }
                // Committed work isn't gone: the turn's and the branch's changes still show it.
                if let review, let session {
                    Button("Show This Turn") { review.showTurn(of: session) }
                        .buttonStyle(.ds(.secondary))
                }
            }
        }
    }

    /// Picking This Turn shows the latest turn as it is now.
    private func scopeBinding(_ review: GitChangesReview) -> Binding<GitChangesScope> {
        Binding(
            get: { review.scope },
            set: { scope in
                if scope == .turn, let session {
                    review.showTurn(of: session)
                } else {
                    review.scope = scope
                }
            })
    }

    private func followLatestTurn() {
        if let review, let session { review.followLatestTurn(of: session) }
    }

    @ViewBuilder private var noticeBanner: some View {
        if let notice = model.notice {
            GitNoticeBanner(notice: notice, onAction: run, onDismiss: model.dismissNotice)
            SeparatorLine()
        }
    }

    private func conflictsBanner(count: Int) -> some View {
        let notice = GitNotice(
            tone: .failure,
            title: count == 1 ? "1 file has conflicts" : "\(count) files have conflicts",
            message: "Edit each one to resolve the conflict markers, then stage it to mark it resolved.",
            action: .showConflicts
        )
        return VStack(spacing: 0) {
            GitNoticeBanner(notice: notice, onAction: run)
            SeparatorLine()
        }
    }

    private func run(_ action: GitNotice.Action) {
        Task { await model.run(action) }
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

    private var cleanMessage: String {
        guard let branch = model.branch else { return "" }
        if branch.isUnborn {
            return "This repository has no commits yet. Changes appear here as files are added."
        }
        if branch.ahead > 0 {
            let commits = branch.ahead == 1 ? "1 commit is" : "\(branch.ahead) commits are"
            return "Everything is committed, and \(commits) ready to push."
        }
        if !model.hasRemote {
            return "Everything is committed. This repository has no remote yet; add one to push."
        }
        if branch.upstream == nil, !branch.isDetached {
            return "Everything is committed. \(branch.displayName) isn't on a remote yet."
        }
        return "Everything on \(branch.displayName) is committed. Changes show up here as files are edited."
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

#if DEBUG
#Preview("Changes inspector") {
    DSPreviewPair {
        GitChangesInspector(model: GitPreviewFixtures.model, onCreatePullRequest: {})
            .frame(width: GitMetrics.inspectorIdealWidth, height: 720)
    }
}

#Preview("Changes inspector - Nothing to commit") {
    DSPreviewPair {
        GitChangesInspector(model: GitPreviewFixtures.cleanModel, onCreatePullRequest: {})
            .frame(width: GitMetrics.inspectorIdealWidth, height: 480)
    }
}
#endif
