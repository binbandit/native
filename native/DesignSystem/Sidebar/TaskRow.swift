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

/// A generic type can't hold static stored properties, so the row's own metrics live here.
private enum TaskRowMetrics {
    /// The archive button's side, and the narrowest the age's slot gets so the button covers it.
    static let archiveSide: CGFloat = 20
}

/// Something worth a glance at a task row's trailing edge.
public enum TaskBadge: Equatable, Sendable {
    /// A 6pt unread dot, in the accent.
    case dot
    /// A short label in the accent, e.g. "Approve".
    case attention(String)
    /// A neutral count, e.g. queued messages.
    case count(Int)
}

/// A task (an agent session) in the sidebar: status glyph, title and a
/// trailing badge, then the diff or age at the trailing edge; 36pt tall with 6pt-rounded hover and
/// selection fills. Unread tasks set their title semibold in the primary color; inline code in a
/// title shows in monospace. With `onArchive`, an archive button takes the age's place on hover
/// (and is offered to VoiceOver as an action); the badge and accessory stay put, so a control
/// there (a pull request badge) can be reached on hover.
///
/// Two optional slots: `leading`, a 16pt type glyph (the agent: `Image(systemName:)` or any view,
/// tinted tertiary), and `accessory`, a view between the badge and the age (e.g.
/// `ContextUsageRing`). The row has one leading visual: the type glyph at rest (idle or done), the
/// status glyph while something is happening or wants the user. See `TaskRow+Slots.swift` for the
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
    ///   - accessory: A small view near the trailing edge, before the age.
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
        let _ = LaunchExperiment.logChanges ? Self._logChanges() : ()
        if LaunchExperiment.rowNoButton { rowContent } else { realBody }
    }

    private var realBody: some View {
        Button(action: action) {
            rowContent
        }
        .buttonStyle(SidebarRowButtonStyle())
        .lxUnless(LaunchExperiment.rowNoA11y) {
            $0.accessibilityLabel(title)
                .accessibilityValue(accessibilityValue)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityActions {
                    if let onArchive {
                        Button("Archive", action: onArchive)
                    }
                }
        }
        .lxUnless(LaunchExperiment.rowNoChrome) {
            $0.overlay(alignment: .topTrailing) {
                if let onArchive, isArchiveShown {
                    // Over the age's slot, which is at least this wide, at the row's trailing inset.
                    Button("Archive", systemImage: "archivebox", action: onArchive)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(.dsTextSecondary)
                        .frame(width: TaskRowMetrics.archiveSide, height: TaskRowMetrics.archiveSide)
                        .contentShape(.rect)
                        .dsHitTarget(TaskRowMetrics.archiveSide)
                        .padding(.top, DS.Space.md)
                        .padding(.trailing, DS.Space.sm)
                        .help("Archive Task")
                }
            }
            .background {
                RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
                    .fill(isSelected ? .dsSelected : isHovered ? .dsHover : .clear)
            }
        }
        .lxUnless(LaunchExperiment.noHover) { $0.trackHover($isHovered) }
    }

    private var rowContent: some View {
        HStack(alignment: .top, spacing: DS.Space.sm) {
            if !LaunchExperiment.rowNoLeading {
                Group {
                    if showsLeading {
                        leading
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.dsTextTertiary)
                            .frame(width: DS.Size.rowLeading, height: DS.Size.rowLeading)
                            .lxUnless(LaunchExperiment.noIconHelp) { $0.help(status.label) }
                    } else {
                        StatusIndicator(status: status)
                    }
                }
                .padding(.top, DS.Space.xxs)
                .padding(.trailing, DS.Space.xxs)
            }

            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                HStack(spacing: DS.Space.sm) {
                    // Titles often carry inline code ("Add `maxLength` option").
                    Group { if LaunchExperiment.noInlineCode { Text(title) } else { DSInlineCodeText(title) } }
                        .font(isUnread ? .dsCalloutSemibold : .dsCalloutBook)
                        .foregroundStyle(isUnread || isSelected ? .dsTextPrimary : .dsTextSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if !LaunchExperiment.rowNoTrailing { trailing }
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
        .frame(minHeight: DS.Size.rowMinHeight)
        .contentShape(.rect)
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

            accessory

            age
                .frame(minWidth: onArchive == nil ? nil : TaskRowMetrics.archiveSide, alignment: .trailing)
                .opacity(isArchiveShown ? 0 : 1)
        }
    }

    @ViewBuilder private var age: some View {
        if let diff, diff.added > 0 || diff.removed > 0 {
            DiffStatLabel(added: diff.added, removed: diff.removed)
        } else if let date {
            CompactAgeText(date: date)
        }
    }

    /// The archive button replaces the age on hover, and always on touch, which has no hover to
    /// reveal it.
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
