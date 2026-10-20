#if DEBUG
import SwiftUI

/// The task row the directions share: a leading mark, the title (semibold while unread), an optional
/// second line, and a trailing slot. It owns hover, selection, the click that opens the task and a
/// short context menu, so each direction only decides what goes where.
struct SidebarDesignRow<Leading: View, Trailing: View>: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager

    let task: SidebarDesignTask
    var detail: String?
    var detailTone: SidebarDesignTone = .quiet
    /// Space before the leading mark, to sit under a header.
    var indent: CGFloat = DS.Space.sm
    /// Taller rows read calmer; denser ones fit more.
    var verticalPadding: CGFloat = DS.Space.md
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing

    @State private var isHovered = false

    private var isSelected: Bool { model.selection == task.id }

    var body: some View {
        Button {
            model.selectFromSidebarDesign(task.id)
        } label: {
            HStack(alignment: .top, spacing: DS.Space.md) {
                leading()
                    .frame(width: DS.Size.rowLeading, height: DS.Size.rowLeading)
                    .padding(.top, DS.Space.xxs)
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    HStack(spacing: DS.Space.sm) {
                        DSInlineCodeText(task.title)
                            .font(task.isUnread ? .dsCalloutSemibold : .dsCalloutBook)
                            .foregroundStyle(task.isUnread || isSelected ? .dsTextPrimary : .dsTextSecondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        trailing()
                    }
                    .frame(height: 20)
                    if let detail {
                        DSInlineCodeText(detail, codeFont: .dsMonoCaption)
                            .font(.dsCaption)
                            .foregroundStyle(detailTone.color)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.bottom, DS.Space.xxs)
                    }
                }
            }
            .padding(.vertical, verticalPadding)
            .padding(.leading, indent)
            .padding(.trailing, DS.Space.sm)
            .contentShape(.rect)
        }
        .buttonStyle(SidebarRowButtonStyle())
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
                .fill(isSelected ? .dsSelected : isHovered ? .dsHover : .clear)
        }
        .trackHover($isHovered)
        .help([task.title, task.detail].compactMap(\.self).joined(separator: "\n"))
        .accessibilityLabel(task.title)
        .accessibilityValue(
            [task.status.label, task.isUnread ? "Unread" : nil, task.detail].compactMap(\.self).joined(separator: ", ")
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .contextMenu {
            Button(task.isUnread ? "Mark as Read" : "Mark as Unread") { model.setUnread(task.id, !task.isUnread) }
            Divider()
            if task.isArchived {
                Button("Unarchive") { Task { await model.unarchiveSession(task.id) } }
            } else {
                Button("Archive") { Task { await model.archiveSession(task.id, undoManager: undoManager) } }
            }
        }
    }
}

/// How loud a row's second line is.
enum SidebarDesignTone {
    case quiet, attention, danger

    var color: Color {
        switch self {
        case .quiet: .dsTextTertiary
        case .attention: .dsAttention
        case .danger: .dsDanger
        }
    }

    init(_ task: SidebarDesignTask) {
        self = task.status.needsAttention ? .attention : task.status == .failed ? .danger : .quiet
    }
}

/// The leading mark of a calm row: the status only while something is happening or wants the user,
/// the unread dot for a result not yet seen, and nothing at rest.
struct SidebarDesignMark: View {
    let task: SidebarDesignTask

    var body: some View {
        if task.isYourMove || task.status.isActive {
            StatusIndicator(status: task.status)
        } else if task.isUnread {
            StatusDot()
        } else {
            Color.clear
        }
    }
}

/// Where a task runs when it isn't this Mac: a small machine glyph and its name. Room for remote
/// hosts; only the fixture fills it today.
struct SidebarDesignDevice: View {
    let name: String
    var showsName = true

    var body: some View {
        HStack(spacing: DS.Space.xxs) {
            Image(systemName: "desktopcomputer")
                .font(.dsMicro)
            if showsName {
                Text(name)
                    .font(.dsCaption)
            }
        }
        .foregroundStyle(.dsTextTertiary)
        .help("Runs on \(name)")
    }
}

/// A row that starts something, quieter than a task: "+ Start a task in sample".
struct SidebarDesignStartRow: View {
    let title: String
    var indent: CGFloat = DS.Space.sm
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.md) {
                Image(systemName: "plus")
                    .font(.dsCaption)
                    .frame(width: DS.Size.rowLeading, height: DS.Size.rowLeading)
                Text(title)
                    .font(.dsCalloutBook)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isHovered ? .dsTextSecondary : .dsTextTertiary)
            .padding(.vertical, DS.Space.md)
            .padding(.leading, indent)
            .padding(.trailing, DS.Space.sm)
            .contentShape(.rect)
        }
        .buttonStyle(SidebarRowButtonStyle())
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
                .fill(isHovered ? .dsHover : .clear)
        }
        .trackHover($isHovered)
    }
}
#endif
