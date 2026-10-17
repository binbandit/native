import SwiftUI

/// What leads a project row.
public enum ProjectIcon {
    /// The project name's first letter on a small tile (Conductor's fallback avatar).
    case initial
    /// An SF Symbol, e.g. "folder".
    case symbol(String)
    /// An emoji the user picked.
    case emoji(String)
    /// An image, e.g. the repository's favicon or owner avatar.
    case image(Image)
}

/// A project header (Conductor's repository row): avatar, name and, while collapsed, the task count.
/// Hovering swaps the avatar for a chevron and reveals the actions menu; "+" creates a task.
public struct ProjectRow<MenuContent: View>: View {
    let name: String
    let icon: ProjectIcon
    let isExpanded: Bool
    let taskCount: Int?
    let onToggle: () -> Void
    let onNewTask: (() -> Void)?
    let menu: MenuContent

    @State private var isHovered = false

    /// - Parameters:
    ///   - taskCount: Shown after the name while collapsed (Conductor shows it in mono).
    ///   - menu: The project's actions, shown from the "…" button and as a context menu.
    public init(
        name: String,
        icon: ProjectIcon = .initial,
        isExpanded: Bool,
        taskCount: Int? = nil,
        onToggle: @escaping () -> Void,
        onNewTask: (() -> Void)? = nil,
        @ViewBuilder menu: () -> MenuContent
    ) {
        self.name = name
        self.icon = icon
        self.isExpanded = isExpanded
        self.taskCount = taskCount
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

                    if !isExpanded, let taskCount, taskCount > 0 {
                        Text("\(taskCount)")
                            .font(.dsMonoCaption)
                            .foregroundStyle(.dsTextTertiary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, DS.Space.sm)
                .padding(.leading, DS.Space.sm)
                .frame(minHeight: 32)
                .contentShape(.rect)
            }
            .buttonStyle(SidebarRowButtonStyle())
            .accessibilityLabel(name)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
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
}

extension ProjectRow where MenuContent == EmptyView {
    public init(
        name: String,
        icon: ProjectIcon = .initial,
        isExpanded: Bool,
        taskCount: Int? = nil,
        onToggle: @escaping () -> Void,
        onNewTask: (() -> Void)? = nil
    ) {
        self.init(name: name, icon: icon, isExpanded: isExpanded, taskCount: taskCount, onToggle: onToggle, onNewTask: onNewTask) {
            EmptyView()
        }
    }
}

/// A 16pt project avatar (Conductor `RepoAvatar`): emoji, image, symbol or a lettered tile.
public struct ProjectAvatar: View {
    let name: String
    let icon: ProjectIcon

    public init(name: String, icon: ProjectIcon = .initial) {
        self.name = name
        self.icon = icon
    }

    public var body: some View {
        Group {
            switch icon {
            case .initial:
                Text(name.first.map { String($0).uppercased() } ?? "?")
                    .font(.ds(10, weight: .medium))
                    .foregroundStyle(.dsTextSecondary)
                    .frame(width: DS.Size.rowLeading, height: DS.Size.rowLeading)
                    .background(.dsSelected, in: .rect(cornerRadius: DS.Radius.control, style: .continuous))
            case .symbol(let name):
                Image(systemName: name)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.dsTextSecondary)
            case .emoji(let emoji):
                Text(emoji)
                    .font(.system(size: 12))
            case .image(let image):
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: DS.Size.rowLeading, height: DS.Size.rowLeading)
                    .clipShape(.rect(cornerRadius: DS.Radius.control, style: .continuous))
            }
        }
        .frame(width: DS.Size.rowLeading, height: DS.Size.rowLeading)
        .accessibilityHidden(true)
    }
}

#Preview("Project rows") {
    DSPreviewPair {
        VStack(spacing: DS.Space.xs) {
            ProjectRow(name: "native", isExpanded: true, onToggle: {}, onNewTask: {}) {
                Button("Reveal in Finder") {}
            }
            ProjectRow(name: "conductor", icon: .symbol("folder"), isExpanded: false, taskCount: 3, onToggle: {}, onNewTask: {})
            ProjectRow(name: "website", icon: .emoji("🌐"), isExpanded: false, taskCount: 1, onToggle: {})
        }
        .frame(width: 244)
    }
}
