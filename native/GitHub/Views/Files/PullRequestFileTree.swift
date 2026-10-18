import GitHub
import SwiftUI

/// The changed files by folder: each with whether it's viewed, open conversations and its size.
/// Clicking one scrolls the diffs to it.
struct PullRequestFileTree: View {
    let model: PullRequestPageModel

    var body: some View {
        let threads = model.openThreadCounts
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(groups, id: \.folder) { group in
                    if !group.folder.isEmpty {
                        Text(group.folder)
                            .font(.dsCaption)
                            .foregroundStyle(.dsTextTertiary)
                            .lineLimit(1)
                            .truncationMode(.head)
                            .padding(.horizontal, DS.Space.md)
                            .padding(.top, DS.Space.md)
                            .padding(.bottom, DS.Space.xxs)
                            .help(group.folder)
                    }
                    ForEach(group.files) { file in
                        PullRequestFileTreeRow(file: file, openThreads: threads[file.path] ?? 0) {
                            model.setCollapsed(false, file)
                            model.focusedFile = file.path
                        }
                    }
                }
            }
            .padding(.vertical, DS.Space.sm)
            .padding(.horizontal, DS.Space.xs)
        }
        .scrollContentBackground(.hidden)
    }

    private var groups: [(folder: String, files: [ChangedFile])] {
        var order: [String] = []
        var byFolder: [String: [ChangedFile]] = [:]
        for file in model.files {
            let folder = (file.path as NSString).deletingLastPathComponent
            if byFolder[folder] == nil { order.append(folder) }
            byFolder[folder, default: []].append(file)
        }
        return order.map { ($0, byFolder[$0] ?? []) }
    }
}

private struct PullRequestFileTreeRow: View {
    let file: ChangedFile
    let openThreads: Int
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.sm) {
                Image(systemName: file.isViewed ? "checkmark.circle.fill" : symbol)
                    .font(.system(size: DS.Size.navIcon - DS.Space.xxs))
                    .foregroundStyle(file.isViewed ? .dsSuccess : tint)
                    .frame(width: DS.Size.navIcon)
                Text((file.path as NSString).lastPathComponent)
                    .font(.dsBody)
                    .foregroundStyle(file.isViewed ? .dsTextTertiary : .dsTextPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: DS.Space.xs)
                if openThreads > 0 {
                    Label("\(openThreads)", systemImage: "text.bubble")
                        .labelStyle(.titleAndIcon)
                        .font(.dsMicro)
                        .foregroundStyle(.dsAttention)
                        .help("\(openThreads) unresolved conversation\(openThreads == 1 ? "" : "s")")
                }
                DiffStatLabel(added: file.additions, removed: file.deletions, isMuted: file.isViewed)
            }
            .padding(.horizontal, DS.Space.sm)
            .frame(minHeight: DS.Size.listRow)
            .background(isHovered ? .dsHover : .clear, in: RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .trackHover($isHovered)
        .help(file.path)
        .accessibilityLabel("\(file.path), \(file.isViewed ? "viewed" : "not viewed")")
    }

    private var symbol: String {
        switch file.changeType {
        case .added: "plus.circle"
        case .deleted: "minus.circle"
        case .renamed, .copied: "arrow.right.circle"
        default: "circle"
        }
    }

    private var tint: Color {
        switch file.changeType {
        case .added: .dsSuccess
        case .deleted: .dsDanger
        default: .dsTextTertiary
        }
    }
}
