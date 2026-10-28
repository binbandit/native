import SwiftUI

/// What leads a project row.
public enum ProjectIcon {
    /// The project name's first letter on a small tile.
    case initial
    /// An SF Symbol, e.g. "folder".
    case symbol(String)
    /// An emoji the user picked.
    case emoji(String)
    /// An image, e.g. the repository's favicon or owner avatar.
    case image(Image)
}

/// A project header: avatar, name and, while collapsed, what its tasks are doing (the needs-you
/// marker and the working loader with their counts) or else the task count, or a note in their
/// place. Hovering swaps the avatar for a chevron and reveals the actions menu; "+" creates a task.
public struct ProjectRow<MenuContent: View>: View {
    let name: String
    let qualifier: String?
    let path: String?
    let icon: ProjectIcon
    let isExpanded: Bool
    let taskCount: Int?
    let isRefreshing: Bool
    let activity: ProjectActivity
    let note: String?
    let onToggle: () -> Void
    let onNewTask: (() -> Void)?
    let menu: MenuContent

    @State private var isHovered = false

    /// - Parameters:
    ///   - taskCount: Shown after the name, in mono, while collapsed and nothing is happening.
    ///   - activity: Shown after the name while collapsed, instead of the count.
    ///   - note: Shown after the name while collapsed, instead of either ("No matching tasks").
    ///   - menu: The project's actions, shown from the "…" button and as a context menu.
    public init(
        name: String,
        qualifier: String? = nil,
        path: String? = nil,
        icon: ProjectIcon = .initial,
        isExpanded: Bool,
        taskCount: Int? = nil,
        activity: ProjectActivity = ProjectActivity(),
        isRefreshing: Bool = false,
        note: String? = nil,
        onToggle: @escaping () -> Void,
        onNewTask: (() -> Void)? = nil,
        @ViewBuilder menu: () -> MenuContent
    ) {
        self.name = name
        self.qualifier = qualifier
        self.path = path
        self.icon = icon
        self.isExpanded = isExpanded
        self.taskCount = taskCount
        self.activity = activity
        self.isRefreshing = isRefreshing
        self.note = note
        self.onToggle = onToggle
        self.onNewTask = onNewTask
        self.menu = menu()
    }

    private var hasMenu: Bool { MenuContent.self != EmptyView.self }

    public var body: some View {
        HStack(spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: DS.Space.md) {
                    ZStack {
                        ProjectAvatar(name: name, icon: icon)
                            .opacity(isHovered ? 0 : 1)
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.dsTextSecondary)
                            .opacity(isHovered ? 1 : 0)
                    }
                    .frame(width: DS.Size.rowLeading, height: DS.Size.rowLeading)

                    Text(name)
                        .font(.dsCalloutSemibold)
                        .foregroundStyle(.dsTextSecondary)
                        .lineLimit(1)

                    if let qualifier {
                        Text("· \(qualifier)")
                            .font(.dsCalloutBook)
                            .foregroundStyle(.dsTextTertiary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }

                    if isRefreshing {
                        ProjectRefreshIndicator()
                    }
                    if !isExpanded {
                        if let note {
                            Text(note)
                                .font(.dsCaption)
                                .foregroundStyle(.dsTextTertiary)
                                .lineLimit(1)
                        } else if !activity.isEmpty {
                            ProjectActivityLabel(activity: activity)
                        } else if let taskCount, taskCount > 0 {
                            Text("\(taskCount)")
                                .font(.dsMonoCaption)
                                .foregroundStyle(.dsTextTertiary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, DS.Space.sm)
                .padding(.leading, DS.Space.sm)
                .frame(minHeight: max(32, DS.Size.minimumHitTarget))
                .contentShape(.rect)
            }
            .buttonStyle(SidebarRowButtonStyle())
            .accessibilityLabel([name, qualifier, path].compactMap { $0 }.joined(separator: ", "))
            .help(path ?? name)
            .accessibilityValue(accessibilityValue)
            .accessibilityHint(isExpanded ? "Hides the project's tasks" : "Shows the project's tasks")

            if hasMenu {
                Menu {
                    menu
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: DS.Size.controlXS, height: DS.Size.controlXS)
                        .contentShape(.rect)
                        .dsHitTarget(DS.Size.controlXS)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .foregroundStyle(.dsTextSecondary)
                // Touch has no hover to reveal it, so it stays.
                .opacity(isHovered || DS.isTouchPlatform ? 1 : 0)
                .help("Project Options")
                .accessibilityLabel("\(name) Options")
            }

            if let onNewTask {
                IconButton("New Task in \(name)", systemImage: "plus", size: .small, action: onNewTask)
            }
        }
        .padding(.trailing, DS.Space.sm)
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
                .fill(isHovered ? .dsHover : .clear)
        }
        .trackHover($isHovered)
        .contextMenu {
            if hasMenu {
                menu
            }
        }
    }

    /// "Collapsed, 1 needs you, 2 working", so VoiceOver hears what the hidden tasks are doing.
    private var accessibilityValue: String {
        if isRefreshing { return "Refreshing task state" }
        guard !isExpanded else { return "Expanded" }
        return ["Collapsed", note ?? activity.label].compactMap(\.self).joined(separator: ", ")
    }
}

extension ProjectRow where MenuContent == EmptyView {
    public init(
        name: String,
        icon: ProjectIcon = .initial,
        isExpanded: Bool,
        taskCount: Int? = nil,
        activity: ProjectActivity = ProjectActivity(),
        onToggle: @escaping () -> Void,
        onNewTask: (() -> Void)? = nil
    ) {
        self.init(
            name: name, icon: icon, isExpanded: isExpanded, taskCount: taskCount, activity: activity,
            onToggle: onToggle, onNewTask: onNewTask
        ) {
            EmptyView()
        }
    }
}

/// A project avatar, 16pt in rows: emoji, image, symbol or a lettered tile. Larger ones (Settings)
/// scale the type and the tile's corner with it. A template image (an SVG drawn in
/// `currentColor`) takes the same secondary foreground as the symbol and the initial.
public struct ProjectAvatar: View {
    let name: String
    let icon: ProjectIcon
    let size: CGFloat

    public init(name: String, icon: ProjectIcon = .initial, size: CGFloat = DS.Size.rowLeading) {
        self.name = name
        self.icon = icon
        self.size = size
    }

    /// How much larger than a row's avatar this one is.
    private var scale: CGFloat { size / DS.Size.rowLeading }

    public var body: some View {
        let tile = RoundedRectangle(cornerRadius: DS.Radius.control * scale, style: .continuous)
        Group {
            switch icon {
            case .initial:
                Text(name.first.map { String($0).uppercased() } ?? "?")
                    .font(.ds(10 * scale, weight: .medium))
                    .foregroundStyle(.dsTextSecondary)
                    .frame(width: size, height: size)
                    .background(.dsSelected, in: tile)
            case .symbol(let name):
                Image(systemName: name)
                    .font(.system(size: 12 * scale, weight: .regular))
                    .foregroundStyle(.dsTextSecondary)
            case .emoji(let emoji):
                Text(emoji)
                    .font(.system(size: 12 * scale))
            case .image(let image):
                image
                    .resizable()
                    .scaledToFill()
                    .foregroundStyle(.dsTextSecondary)
                    .frame(width: size, height: size)
                    .clipShape(tile)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

#Preview("Project rows") {
    DSPreviewPair {
        VStack(spacing: DS.Space.xs) {
            ProjectRow(name: "Refreshing project", isExpanded: true, isRefreshing: true, onToggle: {}) {
                Button("Refresh") {}
            }
            ProjectRow(name: "native", isExpanded: true, onToggle: {}, onNewTask: {}) {
                Button("Reveal in Finder") {}
            }
            ProjectRow(
                name: "companion", icon: .symbol("folder"), isExpanded: false, taskCount: 3, onToggle: {}, onNewTask: {}
            )
            ProjectRow(name: "website", icon: .emoji("🌐"), isExpanded: false, taskCount: 1, onToggle: {})
        }
        .frame(width: 244)
    }
}

#if DEBUG
#Preview("Project names - Duplicates and custom name") {
    DSPreviewPair {
        VStack(spacing: DS.Space.xs) {
            ProjectRow(name: "native", qualifier: "work", path: "/projects/work/native", isExpanded: true, onToggle: {})
            {
                Button("Rename Project…") {}
            }
            ProjectRow(
                name: "native", qualifier: "personal", path: "/projects/personal/native", isExpanded: false,
                onToggle: {}
            ) {
                Button("Rename Project…") {}
            }
            ProjectRow(name: "Native at Work", path: "/projects/work/native", isExpanded: true, onToggle: {}) {
                Button("Rename Project…") {}
            }
        }
        .frame(width: DS.Window.sidebarMinWidth)
    }
}
#endif
