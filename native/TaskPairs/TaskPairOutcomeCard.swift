import ACP
import Git
import SwiftUI

/// After a task of an undecided pair finishes: a record of both versions (what each changed since
/// they started), with Compare and Keep, the two things only this card does. Review stays in the
/// well. Each row opens its version: this task's changes, or the other task.
struct TaskPairOutcomeCard: View {
    /// The task whose transcript the card ends.
    let task: SessionKey
    let pair: TaskPair
    @Environment(AppModel.self) private var model
    @Environment(GitStore.self) private var git: GitStore?
    @Environment(\.undoManager) private var undoManager
    @Environment(\.turnChangesActions) private var changes
    @State private var comparison: TaskPairComparison

    init(task: SessionKey, pair: TaskPair, comparison: TaskPairComparison = TaskPairComparison()) {
        self.task = task
        self.pair = pair
        _comparison = State(initialValue: comparison)
    }

    private var other: SessionKey? { pair.other(than: task) }
    private var isSettled: Bool { model.isTaskPairSettled(pair) }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(pair.tasks, id: \.self) { key in
                if key != pair.tasks.first { SeparatorLine() }
                row(key)
            }
            SeparatorLine()
            footer
        }
        .font(.dsCallout)
        .background(.dsSurface, in: .rect(cornerRadius: DS.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous).strokeBorder(.dsSeparator)
        }
        .task(id: reloadKey) { await load() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Two versions of this task")
    }

    private func row(_ key: SessionKey) -> some View {
        let isThis = key == task
        return Button {
            if isThis { changes?.review() } else { model.selection = key }
        } label: {
            HStack(spacing: DS.Space.md) {
                HStack(spacing: DS.Space.sm) {
                    Text(model.taskPairAgentName(key)).foregroundStyle(isThis ? .dsTextPrimary : .dsTextSecondary)
                    if isThis { Text("this task").font(.dsBody).foregroundStyle(.dsTextTertiary) }
                }
                .lineLimit(1)
                .frame(width: DS.TaskPair.nameWidth, alignment: .leading)
                summary(of: key)
                Spacer(minLength: DS.Space.md)
                Image(systemName: "chevron.right").font(.dsMicro).foregroundStyle(.dsTextQuaternary)
            }
            .padding(.horizontal, DS.Space.lg)
            .frame(height: DS.TaskPair.rowHeight)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(isThis ? "Review this task's changes" : "Open \(model.taskPairAgentName(key))'s task")
    }

    @ViewBuilder private func summary(of key: SessionKey) -> some View {
        if !model.isTaskPairMemberSettled(key) {
            Text(model.session(key)?.taskStatus.needsAttention == true ? "Waiting for you" : "Still working")
                .foregroundStyle(.dsTextTertiary)
        } else if let version = comparison.version(key) {
            if version.changes.isEmpty {
                Text("No files changed").foregroundStyle(.dsTextTertiary)
            } else {
                Text(version.changes.count == 1 ? "1 file changed" : "\(version.changes.count) files changed")
                    .foregroundStyle(.dsTextSecondary)
                DiffStatsText(stats: DiffStats(added: version.totals.additions, removed: version.totals.deletions))
                    .font(.dsMono)
            }
        } else if case .failed = comparison.state {
            Text("Couldn't count the changes").foregroundStyle(.dsTextTertiary)
        } else {
            Text("Counting changes…").foregroundStyle(.dsTextTertiary)
        }
    }

    private var footer: some View {
        HStack(spacing: DS.Space.md) {
            Text(footnote)
                .font(.dsBody).foregroundStyle(failure == nil ? .dsTextTertiary : .dsAttention)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if failure != nil {
                Button("Try Again") { Task { await load() } }
                    .buttonStyle(.ds(.ghost))
            } else {
                Button("Compare") { model.compareTaskPair(containing: task) }
                    .buttonStyle(.ds(.ghost))
                    .disabled(!isSettled)
                    .help("Show both versions side by side, file by file")
            }
            Button("Keep \(model.taskPairAgentName(task))'s") {
                Task { await model.keepTaskPairVersion(task, undoManager: undoManager) }
            }
            .buttonStyle(.ds(.secondary))
            .disabled(!isSettled)
        }
        .padding(.leading, DS.Space.lg)
        .padding(.trailing, DS.Space.md)
        .padding(.vertical, DS.Space.md)
    }

    private var failure: String? {
        if case .failed(let message) = comparison.state { message } else { nil }
    }

    private var footnote: String {
        if let failure { return failure }
        if let other, !model.isTaskPairMemberSettled(other) {
            return "Compare and keep one once \(model.taskPairAgentName(other)) finishes."
        }
        return "Keep one, and the other's worktree goes. Its branch is saved as a checkpoint first."
    }

    private func load() async {
        if let git { await comparison.load(pair, model: model, git: git) }
    }

    /// Reads both worktrees again when either task's turn ends or either checkout rescans.
    private var reloadKey: String {
        pair.tasks.map { key in
            let scans = model.session(key).flatMap { git?.model(for: $0.cwd, session: key).scanCount } ?? 0
            return "\(key.id.rawValue):\(model.isTaskPairMemberSettled(key)):\(scans)"
        }.joined(separator: "|")
    }
}

/// The end of a pair's task: the two versions while the user decides, then which one was kept.
struct TaskPairTranscriptTrailer: View {
    let task: SessionKey
    @Environment(AppModel.self) private var model

    var body: some View {
        if let pair = model.openTaskPair(containing: task) {
            if model.isTaskPairMemberSettled(task) {
                TaskPairOutcomeCard(task: task, pair: pair)
            }
        } else if let pair = model.keptTaskPair(containing: task), let other = pair.other(than: task) {
            Text("Kept over \(model.taskPairAgentName(other))'s version")
                .font(.dsBody).foregroundStyle(.dsTextTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#if DEBUG
#Preview("Pair - Outcome card: both done, one still working, unreadable, kept") {
    DSPreviewPair {
        let fixtures = TaskPairPreviewFixtures.self
        let done = fixtures.app()
        let working = fixtures.app()
        let failed = fixtures.app()
        VStack(spacing: DS.Space.xl) {
            TaskPairOutcomeCard(task: fixtures.claude, pair: fixtures.pair(in: done), comparison: fixtures.ready())
                .environment(done)
            TaskPairOutcomeCard(
                task: fixtures.claude, pair: fixtures.workingPair(in: working), comparison: fixtures.ready()
            )
            .environment(working)
            TaskPairOutcomeCard(
                task: fixtures.claude, pair: fixtures.pair(in: failed),
                comparison: TaskPairComparison(fixed: .failed("Couldn't read Codex's worktree."))
            )
            .environment(failed)
            TaskPairTranscriptTrailer(task: fixtures.claude).environment(fixtures.keptApp())
        }
        .padding(DS.Space.xl)
        .frame(width: 760)
    }
}
#endif
