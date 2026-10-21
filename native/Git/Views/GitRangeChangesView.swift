import Git
import SwiftUI

/// The inspector's This Turn and Branch: every file changed since the turn began (or the branch
/// left its base), committed or not, with the selected file's diff below. When Native can't tell
/// exactly where the turn began, a note says what it compares with instead.
struct GitRangeChangesView: View {
    let repository: GitRepositoryModel
    let review: GitChangesReview
    let request: GitRangeRequest

    @State private var model: GitRangeModel

    /// `model` is for previews, which pass one frozen at a comparison.
    init(
        repository: GitRepositoryModel, review: GitChangesReview, request: GitRangeRequest,
        model: GitRangeModel = GitRangeModel()
    ) {
        self.repository = repository
        self.review = review
        self.request = request
        _model = State(initialValue: model)
    }

    var body: some View {
        VStack(spacing: 0) {
            switch model.state {
            case .loading:
                DotGridLoader(pattern: .settingUp)
                    .foregroundStyle(.dsTextTertiary)
                    .frame(width: GitMetrics.loaderLarge, height: GitMetrics.loaderLarge)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                EmptyStateView(
                    "Couldn't compare the changes", systemImage: "exclamationmark.triangle", message: message
                ) {
                    Button("Try Again") { model.refresh() }
                        .buttonStyle(.ds(.secondary))
                }
            case .ready(let comparison):
                ready(comparison)
            }
        }
        .task(id: request) { show() }
        .onChange(of: review.requestedFile) { show() }
        // Every rescan, not just status changes: an edit can keep its line counts.
        .onChange(of: repository.scanCount) { model.refresh() }
    }

    private func show() {
        guard let repository = repository.repository else { return }
        model.show(request, in: repository, selecting: review.requestedFile)
        review.requestedFile = nil
    }

    @ViewBuilder private func ready(_ comparison: GitRangeComparison) -> some View {
        if let note = Self.note(for: comparison) {
            NoticeBanner(tone: .info, title: note.title, detail: note.detail) {}
                .padding(DS.Space.md)
            SeparatorLine()
        }
        summary(comparison)
        SeparatorLine()
        if comparison.changes.isEmpty {
            emptyState(comparison)
        } else {
            // The list takes what it needs, up to a share of the column, and the diff the rest.
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    GitRangeChangeList(model: model, comparison: comparison, root: repository.localRoot)
                        .frame(
                            height: min(
                                GitRangeChangeList.contentHeight(for: comparison),
                                max(proxy.size.height * GitMetrics.listShare, GitMetrics.listMinHeight)))
                    SeparatorLine()
                    // Reads the selection and its diff itself, so a diff arriving redraws only the pane.
                    GitRangeDiffPane(model: model)
                }
            }
        }
    }

    private func summary(_ comparison: GitRangeComparison) -> some View {
        let totals = comparison.totals
        return HStack(spacing: DS.Space.sm) {
            Text(Self.title(for: comparison))
                .font(.dsBodyMedium)
                .foregroundStyle(.dsTextSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: DS.Space.md)
            DiffStatLabel(added: totals.additions, removed: totals.deletions)
        }
        .padding(.horizontal, DS.Space.lg)
        .frame(height: GitMetrics.summaryHeight)
    }

    @ViewBuilder private func emptyState(_ comparison: GitRangeComparison) -> some View {
        let empty = Self.emptyState(for: comparison, branch: repository.branch?.displayName ?? "This branch")
        EmptyStateView(empty.title, systemImage: empty.systemImage, message: empty.message) {
            if comparison.isTurn, comparison.startsAtTurn {
                Button("Show Branch Changes") { review.scope = .branch }
                    .buttonStyle(.ds(.secondary))
            }
        }
    }

    // MARK: - Words

    /// "1 file changed in this turn", "3 files changed since origin/main".
    static func title(for comparison: GitRangeComparison) -> String {
        let count = comparison.changes.count
        let files = count == 1 ? "1 file changed" : "\(count) files changed"
        if comparison.isTurn {
            if count == 0 { return "Changes in this turn" }
            return comparison.startsAtTurn ? "\(files) in this turn" : "\(files) on this branch"
        }
        return switch comparison.base {
        case .branch(let base): "\(files) since \(base.name)"
        case .head, .turnSnapshot, .turnStartCommit: "\(files), not committed"
        }
    }

    /// Why the comparison isn't exactly the turn's, or the branch's, when it isn't.
    static func note(for comparison: GitRangeComparison) -> (title: String, detail: String)? {
        switch comparison.base {
        case .turnSnapshot:
            return nil
        case .turnStartCommit(let startedAt):
            return (
                "Compared with the last commit before this turn",
                "Native didn't record how the folder looked when this turn began, at "
                    + "\(DSFormat.time(startedAt, now: .now)), so changes that weren't committed then show here too."
            )
        case .branch, .head:
            if comparison.isTurn {
                return (
                    "Showing the branch's changes",
                    "Native didn't see this turn begin, so it can't tell the turn's changes from the rest. The "
                        + "files it edited come first."
                )
            }
            guard case .head = comparison.base else { return nil }
            return (
                "Nothing to compare this branch with",
                "It has no upstream and no default branch to start from, so this shows what isn't committed."
            )
        }
    }

    static func emptyState(
        for comparison: GitRangeComparison, branch: String
    ) -> (title: String, systemImage: String, message: String) {
        let edited = comparison.editedPaths.sorted()
        switch comparison.base {
        case .turnSnapshot, .turnStartCommit:
            if let only = edited.first, edited.count == 1 {
                return (
                    "This turn's changes were undone", "arrow.uturn.backward.circle",
                    "The agent edited \(URL(filePath: only).lastPathComponent), and it's back to how it was when "
                        + "the turn began."
                )
            }
            if !edited.isEmpty {
                return (
                    "This turn's changes were undone", "arrow.uturn.backward.circle",
                    "The agent edited \(edited.count) files, and they're back to how they were when the turn began."
                )
            }
            return ("No changes in this turn", "checkmark.circle", "This turn didn't change any files.")
        case .branch(let base):
            if comparison.isTurn {
                return (
                    "Already in \(base.name)", "checkmark.circle",
                    "Nothing on this branch differs from \(base.name), so this turn's edits are already there."
                )
            }
            return ("No changes on \(branch)", "checkmark.circle", "Everything on it is already in \(base.name).")
        case .head:
            if comparison.isTurn {
                return (
                    "Everything is committed", "checkmark.circle",
                    "There's nothing to compare the commits with, so the edit rows in the transcript are the best "
                        + "record of what this turn changed."
                )
            }
            return (
                "No changes", "checkmark.circle",
                "Nothing is uncommitted, and there's nothing to compare \(branch) with."
            )
        }
    }
}

/// The selected file's diff, reading only the model's shown diff.
private struct GitRangeDiffPane: View {
    let model: GitRangeModel

    var body: some View {
        VStack(spacing: 0) {
            if let shown = model.shownDiff {
                GitFileDiffView(
                    kind: shown.change.kind, path: shown.change.path, stats: shown.change.stats,
                    content: shown.content, onLoadDiff: model.expandSelectedDiff)
            } else {
                EmptyStateView("No file selected", systemImage: "doc.text")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.dsSurface)
    }
}

#if DEBUG
#Preview("This Turn") {
    DSPreviewPair {
        GitRangeChangesView(
            repository: GitPreviewFixtures.cleanModel, review: GitChangesReview(),
            request: .turn(GitPreviewFixtures.turn),
            model: GitRangeModel(fixed: GitPreviewFixtures.turnComparison(.turnSnapshot), diff: GitPreviewFixtures.diff)
        )
        .frame(width: GitMetrics.inspectorIdealWidth, height: 560)
    }
}

#Preview("This Turn - Start not recorded") {
    DSPreviewPair {
        GitRangeChangesView(
            repository: GitPreviewFixtures.cleanModel, review: GitChangesReview(),
            request: .turn(GitPreviewFixtures.turn),
            model: GitRangeModel(
                fixed: GitPreviewFixtures.turnComparison(.turnStartCommit(.now.addingTimeInterval(-600))),
                diff: GitPreviewFixtures.diff)
        )
        .frame(width: GitMetrics.inspectorIdealWidth, height: 560)
    }
}

#Preview("This Turn - Undone") {
    DSPreviewPair {
        GitRangeChangesView(
            repository: GitPreviewFixtures.cleanModel, review: GitChangesReview(),
            request: .turn(GitPreviewFixtures.turn),
            model: GitRangeModel(fixed: GitPreviewFixtures.turnComparison(.turnSnapshot, changes: []))
        )
        .frame(width: GitMetrics.inspectorIdealWidth, height: 420)
    }
}

#Preview("Branch") {
    DSPreviewPair {
        GitRangeChangesView(
            repository: GitPreviewFixtures.cleanModel, review: GitChangesReview(), request: .branch,
            model: GitRangeModel(fixed: GitPreviewFixtures.branchComparison, diff: GitPreviewFixtures.diff)
        )
        .frame(width: GitMetrics.inspectorIdealWidth, height: 560)
    }
}
#endif
