import Git
import SwiftUI

/// One file chooser for the full-width review, including the comparison scope.
struct GitChangesFileMenu: View {
    let model: GitRepositoryModel
    let review: GitChangesReview?
    let scope: Binding<GitChangesScope>?

    private var range: GitRangeModel? {
        switch review?.scope ?? .uncommitted {
        case .uncommitted: nil
        case .turn: review?.turnRange
        case .branch: review?.branchRange
        }
    }

    private var path: String? {
        if let range { return range.shownDiff?.change.path }
        if review?.scope == .turn { return nil }
        return model.shownDiff?.change.path
    }

    private var stats: LineStats? {
        if let range { return range.shownDiff?.change.stats }
        return model.shownDiff?.change.stats
    }

    private var position: String {
        if let range, let comparison = range.comparison {
            guard let index = comparison.changes.firstIndex(where: { $0.path == path }) else { return "" }
            return "\(index + 1) of \(comparison.changes.count) files"
        }
        guard let index = model.changes.firstIndex(where: { $0.id == model.shownDiff?.change.id }) else { return "" }
        let noun = Set(model.changes.map(\.path)).count == model.changes.count ? "files" : "changes"
        return "\(index + 1) of \(model.changes.count) \(noun)"
    }

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            Menu {
                if let scope {
                    Picker("Changes to show", selection: scope) {
                        ForEach(GitChangesScope.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Divider()
                }
                if let range {
                    ForEach(range.comparison?.changes ?? [], id: \.path) { change in
                        Button {
                            range.selection = change.path
                        } label: {
                            Label(
                                change.path,
                                systemImage: range.selection == change.path ? "checkmark" : change.kind.symbolName)
                        }
                    }
                } else if review?.scope != .turn {
                    ForEach(FileChange.Area.allCases, id: \.self) { area in
                        let changes = model.changes.filter { $0.area == area }
                        if !changes.isEmpty {
                            Section(area.title) {
                                ForEach(changes) { change in
                                    Button {
                                        model.selection = change.id
                                    } label: {
                                        Label(
                                            change.path,
                                            systemImage: model.selection == change.id
                                                ? "checkmark" : change.kind.symbolName)
                                    }
                                }
                            }
                        }
                    }
                    if let shown = stageable {
                        Divider()
                        Button(stageTitle(shown)) { toggleStaged(shown) }
                    }
                }
            } label: {
                HStack(spacing: DS.Space.sm) {
                    Text(path.map { URL(filePath: $0).lastPathComponent } ?? "Changes")
                        .font(.dsBodyMedium)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(DS.TaskWell.shortcut)
                        .foregroundStyle(.dsTextTertiary)
                }
                .padding(.horizontal, DS.Space.md)
                .frame(height: DS.Size.controlXS)
                .background(.dsFill, in: RoundedRectangle(cornerRadius: DS.Radius.row))
                .dsHitTarget(DS.Size.controlXS)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("Choose changed file")
            .help([path, (review?.scope ?? .uncommitted).title].compactMap { $0 }.joined(separator: " · "))
            Text(position)
                .font(.dsCaption)
                .foregroundStyle(.dsTextTertiary)
                .lineLimit(1)
                .layoutPriority(-1)
            if let stats, !stats.isBinary {
                DiffStatLabel(added: stats.additions, removed: stats.deletions)
                    .fixedSize()
            }
            // Commit waits on staged conflicts, and there's no list here to stage them from.
            if let shown = stageable, shown.area == .conflicted {
                Button("Stage") { toggleStaged(shown) }
                    .buttonStyle(.ds(.secondary))
                    .help("Mark \(URL(filePath: shown.path).lastPathComponent) resolved")
                    .fixedSize()
            }
        }
    }

    /// The uncommitted change on show, which the menu can stage or unstage in place of the list.
    private var stageable: FileChange? {
        guard range == nil, review?.scope != .turn else { return nil }
        return model.shownDiff?.change
    }

    private func stageTitle(_ change: FileChange) -> String {
        let name = URL(filePath: change.path).lastPathComponent
        return change.area == .staged ? "Unstage \(name)" : "Stage \(name)"
    }

    private func toggleStaged(_ change: FileChange) {
        Task { change.area == .staged ? await model.unstage([change]) : await model.stage([change]) }
    }
}

#if DEBUG
#Preview("Changes file menu - Uncommitted, conflicted and empty") {
    let conflicted = GitRepositoryModel(
        folder: URL(filePath: "/Users/preview/Developer/native"),
        fixedStatus: RepositoryStatus(
            branch: GitPreviewFixtures.branch,
            changes: [
                FileChange(
                    path: "native/DesignSystem/Diff/DiffRow.swift", kind: .conflicted, area: .conflicted,
                    stats: LineStats(additions: 14, deletions: 4))
            ], totals: LineStats(additions: 14, deletions: 4)),
        diff: GitPreviewFixtures.diff)
    return DSPreviewPair {
        VStack(spacing: DS.Space.lg) {
            GitChangesFileMenu(model: GitPreviewFixtures.model, review: nil, scope: nil)
            GitChangesFileMenu(model: conflicted, review: nil, scope: nil)
            GitChangesFileMenu(model: GitPreviewFixtures.cleanModel, review: nil, scope: nil)
        }
        .frame(width: DS.TaskWell.width)
    }
}
#endif
