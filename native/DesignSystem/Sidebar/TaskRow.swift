import SwiftUI

/// How far a task row is indented: under a project header, or flush in a flat list.
public enum TaskRowIndent: Sendable {
    case grouped, flat

    var leading: CGFloat {
        switch self {
        case .grouped: 20
        case .flat: DS.Space.sm
        }
    }
}

/// Something worth a glance at a task row's trailing edge.
public enum TaskBadge: Equatable, Sendable {
    /// Factory's 6pt unread dot, in the accent.
    case dot
    /// A short label in the accent, e.g. "Approve".
    case attention(String)
    /// A neutral count, e.g. queued messages.
    case count(Int)
}

/// A task (an agent session) in the sidebar (Conductor `WorkspaceRow`): status glyph, title and a
/// trailing badge, diff or age; 36pt tall with 6pt-rounded hover and selection fills. Unread tasks
/// set their title semibold in the primary color. With `onArchive`, an archive button takes the
/// trailing items' place on hover (and is offered to VoiceOver as an action).
///
/// Two optional slots: `leading`, a 16pt type glyph (the agent: `Image(systemName:)` or any view,
/// tinted tertiary), and `accessory`, a view after the age (e.g. `ContextUsageRing`). Like
/// Conductor, the row has one leading visual: the type glyph at rest (idle or done), the status
/// glyph while something is happening or wants the user. See `TaskRow+Slots.swift` for the
/// initializers without slots.
public struct TaskRow<Leading: View, Accessory: View>: View {
    let title: String
    let status: TaskStatus
    let isSelected: Bool
    let isUnread: Bool
    let subtitle: String?
    let date: Date?
    let diff: (added: Int, removed: Int)?
    let badge: TaskBadge?
    let indent: TaskRowIndent
    let leading: Leading
    let accessory: Accessory
    let action: () -> Void
    let onArchive: (() -> Void)?

    @State private var isHovered = false

    /// - Parameters:
    ///   - subtitle: A second line, e.g. the branch or agent.
    ///   - date: When the task last changed, shown as a compact age ("now", "5m", "4d").
    ///   - diff: Lines added and removed in the task's worktree; shown instead of the age.
    ///   - leading: An icon before the status glyph, framed at 16pt.
    ///   - accessory: A small view at the trailing edge, after the age.
    public init(
        title: String,
        status: TaskStatus,
        isSelected: Bool = false,
        isUnread: Bool = false,
        subtitle: String? = nil,
        date: Date? = nil,
        diff: (added: Int, removed: Int)? = nil,
        badge: TaskBadge? = nil,
        indent: TaskRowIndent = .grouped,
        leading: Leading,
        accessory: Accessory,
        action: @escaping () -> Void,
        onArchive: (() -> Void)? = nil
    ) {
        self.title = title
        self.status = status
        self.isSelected = isSelected
        self.isUnread = isUnread
        self.subtitle = subtitle
        self.date = date
        self.diff = diff
        self.badge = badge
        self.indent = indent
        self.leading = leading
        self.accessory = accessory
        self.action = action
        self.onArchive = onArchive
    }

    public var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: DS.Space.sm) {
                Group {
                    if showsLeading {
                        leading
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.dsTextTertiary)
                            .frame(width: DS.Size.rowLeading, height: DS.Size.rowLeading)
                            .help(status.label)
                    } else {
                        StatusIndicator(status: status)
                    }
                }
                .padding(.top, DS.Space.xxs)
                .padding(.trailing, DS.Space.xxs)

                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    HStack(spacing: DS.Space.sm) {
                        Text(title)
                            .font(isUnread ? .dsCalloutSemibold : .dsCalloutBook)
                            .foregroundStyle(isUnread || isSelected ? .dsTextPrimary : .dsTextSecondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        trailing
                            .opacity(isArchiveShown ? 0 : 1)
                    }
                    .frame(height: 20)

                    if let subtitle {
                        Text(subtitle)
                            .font(.dsCaption)
                            .foregroundStyle(.dsTextTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .padding(.bottom, DS.Space.xxs)
                    }
                }
            }
            .padding(.vertical, DS.Space.md)
            .padding(.leading, indent.leading)
            .padding(.trailing, DS.Space.sm)
            .contentShape(.rect)
        }
        .buttonStyle(SidebarRowButtonStyle())
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityActions {
            if let onArchive {
                Button("Archive", action: onArchive)
            }
        }
        .overlay(alignment: .topTrailing) {
            if let onArchive, isArchiveShown {
                Button("Archive", systemImage: "archivebox", action: onArchive)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.dsTextSecondary)
                    .frame(width: 20, height: 20)
                    .contentShape(.rect)
                    .dsHitTarget(20)
                    .padding(.top, DS.Space.md)
                    .padding(.trailing, DS.Space.xs)
                    .help("Archive Task")
            }
        }
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
                .fill(isSelected ? .dsSelected : isHovered ? .dsHover : .clear)
        }
        .trackHover($isHovered)
    }

    private var trailing: some View {
        HStack(spacing: DS.Space.sm) {
            switch badge {
            case .dot:
                StatusDot()
            case .attention(let label):
                Text(label)
                    .font(.dsCaptionMedium)
                    .foregroundStyle(.dsAttention)
                    .lineLimit(1)
            case .count(let count):
                Text("\(count)")
                    .font(.dsMonoMicro)
                    .foregroundStyle(.dsTextSecondary)
                    .padding(.horizontal, DS.Space.xs)
                    .frame(minWidth: 16, minHeight: 14)
                    .background(.dsSelected, in: .capsule)
            case nil:
                EmptyView()
            }

            if let diff, diff.added > 0 || diff.removed > 0 {
                DiffStatLabel(added: diff.added, removed: diff.removed)
            } else if let date {
                CompactAgeText(date: date)
            }

            accessory
        }
    }

    /// The archive button replaces the trailing items on hover, and always on touch, which has
    /// no hover to reveal it.
    private var isArchiveShown: Bool {
        onArchive != nil && (isHovered || DS.isTouchPlatform)
    }

    /// The type glyph stands in for the status at rest.
    private var showsLeading: Bool {
        Leading.self != EmptyView.self && (status == .idle || status == .done)
    }

    private var accessibilityValue: String {
        [status.label, isUnread ? "Unread" : nil, subtitle].compactMap(\.self).joined(separator: ", ")
    }
}

#Preview("Task rows") {
    DSPreviewPair {
        VStack(spacing: DS.Space.xs) {
            ForEach(GalleryFixtures.tasks) { task in
                TaskRow(task, action: {})
            }
            TaskRow(
                title: "With agent and context",
                status: .working,
                date: .now,
                leading: Image(systemName: "sparkle"),
                accessory: ContextUsageRing(fraction: 0.82),
                action: {}
            )
        }
        .frame(width: 260)
    }
}
