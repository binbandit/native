import AppKit
import Git
import SwiftUI

/// The changed files, grouped by where they live: conflicts, staged, unstaged, untracked. Each
/// group's header stages or unstages the whole group.
struct GitChangeList: View {
    let model: GitRepositoryModel
    /// Asks for confirmation before anything is thrown away.
    let onDiscard: ([FileChange]) -> Void

    var body: some View {
        let status = model.status
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DS.Space.xxs) {
                ForEach(FileChange.Area.allCases, id: \.self) { area in
                    let changes = status?.changes(in: area) ?? []
                    if !changes.isEmpty {
                        section(area, changes: changes)
                    }
                }
                if let omitted = status?.omittedUntrackedCount, omitted > 0 {
                    Text("\(omitted) more untracked files not shown")
                        .font(.dsCaption)
                        .foregroundStyle(.dsTextTertiary)
                        .padding(.horizontal, DS.Space.md)
                        .padding(.vertical, DS.Space.sm)
                }
            }
            .padding(.horizontal, DS.Space.sm)
            .padding(.bottom, DS.Space.md)
        }
    }

    /// The list's height with nothing scrolled away, so the diff below can have the rest.
    static func contentHeight(for status: RepositoryStatus) -> CGFloat {
        let sections = CGFloat(Set(status.changes.map(\.area)).count)
        let rows = CGFloat(status.changes.count + (status.omittedUntrackedCount > 0 ? 1 : 0))
        return sections * (DS.Size.controlXS + DS.Space.sm + DS.Space.xxs) + rows * GitMetrics.rowHeight + DS.Space.md
    }

    private func section(_ area: FileChange.Area, changes: [FileChange]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Space.sm) {
                Text(area.title)
                    .font(.dsBody)
                    .foregroundStyle(.dsTextTertiary)
                Text("\(changes.count)")
                    .font(.dsMonoCaption)
                    .foregroundStyle(.dsTextQuaternary)
                Spacer(minLength: DS.Space.md)
                if area != .staged {
                    IconButton("Discard All \(area.title)", systemImage: "arrow.uturn.backward") { onDiscard(changes) }
                }
                IconButton(
                    area == .staged ? "Unstage All" : "Stage All", systemImage: area == .staged ? "minus" : "plus"
                ) {
                    Task { area == .staged ? await model.unstage(changes) : await model.stage(changes) }
                }
            }
            .tracking(DS.Tracking.tight)
            .padding(.leading, DS.Space.md)
            .frame(height: DS.Size.controlXS)
            .padding(.top, DS.Space.sm)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(area.title), \(changes.count) files")
            ForEach(changes) { change in
                GitChangeRow(
                    change: change,
                    isSelected: model.selection == change.id,
                    onSelect: { model.selection = change.id },
                    onToggleStaged: {
                        Task { change.area == .staged ? await model.unstage([change]) : await model.stage([change]) }
                    },
                    onDiscard: { onDiscard([change]) }
                )
                .contextMenu { menu(for: change) }
            }
        }
    }

    @ViewBuilder private func menu(for change: FileChange) -> some View {
        Button(change.area == .staged ? "Unstage" : "Stage") {
            Task { change.area == .staged ? await model.unstage([change]) : await model.stage([change]) }
        }
        Button("Discard Changes…", role: .destructive) { onDiscard([change]) }
        Divider()
        if let root = model.repository?.root {
            let url = root.appending(path: change.path)
            Button("Open") { NSWorkspace.shared.open(url) }
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(change.path, forType: .string)
        }
    }
}
