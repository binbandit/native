import ACP
import Git
import SwiftUI

/// Both versions of a brief side by side, file by file: what each changed since they started, the
/// same file's changes next to each other, and the files only one of them touched. Keep sits on
/// each side. Escape, or the well, goes back to the task.
struct TaskPairComparePage: View {
    /// The task Compare was opened from; its version is on the left.
    let task: SessionKey
    let pair: TaskPair
    @Environment(AppModel.self) private var model
    @Environment(GitStore.self) private var git: GitStore?
    @Environment(\.undoManager) private var undoManager
    @State private var comparison: TaskPairComparison
    /// The files showing their lines; the first one opens on its own.
    @State private var expanded: Set<String> = []
    @State private var hasExpandedFirst = false

    init(task: SessionKey, pair: TaskPair, comparison: TaskPairComparison = TaskPairComparison()) {
        self.task = task
        self.pair = pair
        _comparison = State(initialValue: comparison)
    }

    /// This task's version first, then the other.
    private var order: [SessionKey] {
        [task] + pair.tasks.filter { $0 != task }
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.dsBackground)
            .dsToolbarBand()
            .navigationTitle(DSInlineCode.plain(model.titleOfSession(task)))
            .toolbar(removing: .title)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text(DSInlineCode.plain(model.titleOfSession(task))).font(.dsCalloutSemibold).lineLimit(1)
                        Text(subtitle).font(.dsCaption).foregroundStyle(.dsTextTertiary).lineLimit(1)
                    }
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .principal) {
                    Button(action: model.closeTaskPairComparison) {
                        TaskWellLabel(
                            content: TaskWellContent(
                                status: .idle, agent: "", verb: "Comparing",
                                object: order.map(model.taskPairAgentName).joined(separator: " and "),
                                objectIsCode: false, exitKey: "esc"))
                    }
                    .buttonStyle(.plain)
                    .help("Back to the task (Escape)")
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .background {
                // Escape leaves Compare wherever focus is, as it closes a sheet.
                Button("Back to the Task", action: model.closeTaskPairComparison)
                    .keyboardShortcut(.cancelAction)
                    .opacity(0)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
            .task(id: pair.tasks) {
                await load()
                if !hasExpandedFirst, let first = comparison.paths.first {
                    expanded.insert(first)
                    hasExpandedFirst = true
                }
            }
    }

    @ViewBuilder private var content: some View {
        switch comparison.state {
        case .loading:
            LoadingStateView("Reading both versions…")
        case .failed(let message):
            EmptyStateView(
                "Couldn't Compare the Versions", systemImage: "exclamationmark.triangle", message: message,
                actionTitle: "Try Again"
            ) {
                Task { await load() }
            }
        case .ready(_, let versions):
            let sides = order.compactMap { key in versions.first { $0.task == key } }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    columns(sides) { version in TaskPairVersionHeader(version: version) { keep(version.task) } }
                    if comparison.paths.isEmpty {
                        Text("Neither version changed a file yet. Keep one to carry on with it.")
                            .font(.dsBody).foregroundStyle(.dsTextTertiary)
                            .padding(.top, DS.Space.xl)
                    }
                    ForEach(comparison.paths, id: \.self) { path in
                        file(path, sides: sides)
                    }
                    Text(
                        "Keep one and the other's worktree goes, its branch saved as a checkpoint first. Escape goes back to the task."
                    )
                    .font(.dsBody).foregroundStyle(.dsTextTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, DS.Space.xl)
                }
                .padding(DS.TaskPair.pagePadding)
            }
        }
    }

    private func file(_ path: String, sides: [TaskPairComparison.Version]) -> some View {
        let isExpanded = expanded.contains(path)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.reveal) {
                    if isExpanded { expanded.remove(path) } else { expanded.insert(path) }
                }
            } label: {
                columns(sides) { version in
                    TaskPairFileHeader(change: version.change(at: path), path: path, isExpanded: isExpanded)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(URL(filePath: path).lastPathComponent)
            .accessibilityHint(isExpanded ? "Hides both versions' lines" : "Shows both versions' lines")
            if isExpanded {
                columns(sides) { version in
                    TaskPairFileDiff(version: version, change: version.change(at: path))
                }
                .transition(RevealTransition())
            }
        }
        .padding(.top, DS.Space.md)
    }

    /// Two equal columns, one per version.
    private func columns<Column: View>(
        _ sides: [TaskPairComparison.Version], @ViewBuilder column: @escaping (TaskPairComparison.Version) -> Column
    ) -> some View {
        HStack(alignment: .top, spacing: DS.TaskPair.columnGap) {
            ForEach(sides) { version in
                column(version).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func load() async {
        if let git { await comparison.load(pair, model: model, git: git) }
    }

    private func keep(_ key: SessionKey) {
        Task { await model.keepTaskPairVersion(key, undoManager: undoManager) }
    }

    private var subtitle: String {
        let project = model.catalog.lookup(task).flatMap { model.projects.project($0.project)?.name }
        return [project, comparison.version(task)?.branch].compactMap(\.self).joined(separator: " · ")
    }
}

/// One version's heading in Compare: the agent, its branch and counts, and Keep.
private struct TaskPairVersionHeader: View {
    let version: TaskPairComparison.Version
    let keep: () -> Void

    var body: some View {
        HStack(spacing: DS.Space.md) {
            Text(version.agent).font(.dsHeadline).foregroundStyle(.dsTextPrimary).lineLimit(1)
            if let branch = version.branch {
                Text(branch).font(.dsMonoCaption).foregroundStyle(.dsTextTertiary).lineLimit(1).truncationMode(.middle)
            }
            DiffStatsText(stats: DiffStats(added: version.totals.additions, removed: version.totals.deletions))
                .font(.dsMonoCaption)
            Spacer(minLength: DS.Space.md)
            Text(version.changes.count == 1 ? "1 file" : "\(version.changes.count) files")
                .font(.dsBody).foregroundStyle(.dsTextTertiary)
            Button("Keep \(version.agent)'s", action: keep).buttonStyle(.ds(.secondary))
        }
        .padding(.leading, DS.Space.lg)
        .padding(.trailing, DS.Space.md)
        .frame(height: DS.TaskPair.versionHeight)
        .background(.dsSurface, in: .rect(cornerRadius: DS.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous).strokeBorder(.dsSeparator)
        }
    }
}

/// A file's name and counts in one version, or that this version didn't touch it.
private struct TaskPairFileHeader: View {
    let change: TreeChange?
    let path: String
    let isExpanded: Bool

    var body: some View {
        HStack(spacing: DS.Space.md) {
            if let change {
                Text(URL(filePath: path).lastPathComponent).font(.dsMono).foregroundStyle(.dsTextPrimary)
                    .lineLimit(1).truncationMode(.middle)
                    .help(path)
                if let stats = change.stats, !stats.isBinary {
                    DiffStatsText(stats: DiffStats(added: stats.additions, removed: stats.deletions))
                        .font(.dsMonoCaption)
                }
                Spacer(minLength: DS.Space.md)
                if let caption = Self.caption(of: change) {
                    Text(caption).font(.dsBody).foregroundStyle(.dsTextTertiary).lineLimit(1)
                }
            } else {
                Text("Not in this version").font(.dsBody).foregroundStyle(.dsTextTertiary)
                Spacer(minLength: DS.Space.md)
            }
            if !isExpanded {
                HStack(spacing: DS.Space.xs) {
                    Image(systemName: "chevron.right").font(.dsMicro)
                    Text("Show")
                }
                .font(.dsBody).foregroundStyle(.dsTextTertiary)
            }
        }
        .frame(height: DS.TaskPair.fileRowHeight)
    }

    private static func caption(of change: TreeChange) -> String? {
        switch change.kind {
        case .added: "New file"
        case .deleted: "Deleted"
        case .renamed: change.originalPath.map { "Renamed from \(URL(filePath: $0).lastPathComponent)" } ?? "Renamed"
        default: nil
        }
    }
}

/// One version's lines for a file, read when the file opens.
private struct TaskPairFileDiff: View {
    let version: TaskPairComparison.Version
    let change: TreeChange?
    @State private var content: GitDiffContent?
    @State private var loadsInFull = false

    var body: some View {
        Group {
            if change == nil {
                note("Not in this version")
            } else {
                switch content {
                case nil:
                    note("Reading…")
                case .text(let diff)?:
                    DiffView(
                        path: diff.path, oldText: diff.oldText, newText: diff.newText, layout: diff.layout,
                        isEmbedded: true)
                case .collapsed?:
                    Button("Show the Whole Change") { loadsInFull = true }
                        .buttonStyle(.ds(.ghost))
                        .frame(maxWidth: .infinity)
                        .padding(DS.Space.lg)
                case .binary?:
                    note("Binary file")
                case .tooLarge?:
                    note("Too large to show here")
                case .submodule?:
                    note("Submodule")
                case .unavailable(let reason)?:
                    note(reason)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.dsSurface, in: .rect(cornerRadius: DS.Radius.card, style: .continuous))
        .clipShape(.rect(cornerRadius: DS.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous).strokeBorder(.dsSeparator)
        }
        .task(id: "\(version.target)/\(change?.path ?? "")/\(loadsInFull)") {
            guard let change else { return }
            content = await version.diff(change, loadsInFull)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.dsBody).foregroundStyle(.dsTextTertiary)
            .frame(maxWidth: .infinity, minHeight: DS.TaskPair.versionHeight)
    }
}

#if DEBUG
#Preview("Pair - Compare") {
    DSPreviewPair {
        let app = TaskPairPreviewFixtures.app()
        NavigationStack {
            TaskPairComparePage(
                task: TaskPairPreviewFixtures.claude, pair: TaskPairPreviewFixtures.pair(in: app),
                comparison: TaskPairPreviewFixtures.ready())
        }
        .environment(app)
        .frame(width: 1100, height: 720)
    }
}

#Preview("Pair - Compare: reading, unreadable, nothing changed") {
    DSPreviewPair {
        let app = TaskPairPreviewFixtures.app()
        HStack(spacing: DS.Space.xl) {
            let states = [
                TaskPairComparison(),
                TaskPairComparison(fixed: .failed("Couldn't read Codex's worktree.")),
                TaskPairComparison(fixed: .ready(base: "base", versions: [])),
            ]
            ForEach(states.indices, id: \.self) { index in
                let comparison = states[index]
                TaskPairComparePage(
                    task: TaskPairPreviewFixtures.claude, pair: TaskPairPreviewFixtures.pair(in: app),
                    comparison: comparison
                )
                .frame(width: 360, height: 300)
            }
        }
        .environment(app)
    }
}
#endif
