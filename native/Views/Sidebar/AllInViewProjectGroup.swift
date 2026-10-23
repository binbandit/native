import SwiftUI

extension EnvironmentValues {
    /// A presentation choice passed by the sidebar's single experiment site.
    @Entry var sidebarAllInView = false
}

/// All in view's project header. The existing section owns actions and persistence; this view
/// gives the name room and reveals its controls on hover, keyboard focus or touch.
struct AllInViewProjectGroup<MenuContent: View, Content: View>: View {
    let name: String
    var isFirst = false
    @Binding var isExpanded: Bool
    let taskCount: Int
    let activity: ProjectActivity
    let note: String?
    let onNewTask: (() -> Void)?
    @ViewBuilder let menu: () -> MenuContent
    @ViewBuilder let content: () -> Content

    @State private var isHovered = false
    @FocusState private var focusedControl: Control?

    private enum Control: Hashable {
        case disclosure, menu, newTask
    }

    private var showsControls: Bool { isHovered || focusedControl != nil || DS.isTouchPlatform }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Space.xxs) {
                Button {
                    withAnimation(.dsDisclosure) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: DS.Space.sm) {
                        Text(name)
                            .font(DS.Sidebar.projectFont)
                            .tracking(DS.Sidebar.headerTracking)
                            .foregroundStyle(.dsTextSecondary)
                            .lineLimit(1)
                        if !isExpanded {
                            if let note {
                                Text(note)
                                    .font(.dsCaption)
                                    .foregroundStyle(.dsTextTertiary)
                                    .lineLimit(1)
                            } else if !activity.isEmpty {
                                ProjectActivityLabel(activity: activity)
                            } else if taskCount > 0 {
                                Text("\(taskCount)")
                                    .font(.dsMonoCaption)
                                    .foregroundStyle(.dsTextTertiary)
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.dsMicro)
                            .foregroundStyle(.dsTextTertiary)
                            .opacity(showsControls || !isExpanded ? 1 : 0)
                    }
                    .padding(.leading, DS.Sidebar.headerLeading)
                    .frame(minHeight: max(DS.Sidebar.headerHeight, DS.Size.minimumHitTarget))
                    .contentShape(.rect)
                }
                .buttonStyle(SidebarRowButtonStyle())
                .focused($focusedControl, equals: .disclosure)
                .accessibilityLabel(name)
                .accessibilityValue(
                    isExpanded ? "Expanded" : "Collapsed, \(note ?? activity.label ?? "\(taskCount) tasks")"
                )
                .help(isExpanded ? "Hide tasks in \(name)" : "Show tasks in \(name)")

                Menu(content: menu) {
                    Label("\(name) Options", systemImage: "ellipsis")
                }
                .focused($focusedControl, equals: .menu)
                .labelStyle(.iconOnly)
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .font(.dsCaption)
                .foregroundStyle(.dsTextSecondary)
                .dsHitTarget(DS.Size.controlXS)
                .opacity(showsControls ? 1 : 0)
                .help("Project Options")

                if let onNewTask {
                    IconButton("New Task in \(name)", systemImage: "plus", size: .small, action: onNewTask)
                        .focused($focusedControl, equals: .newTask)
                        .opacity(showsControls ? 1 : 0)
                }
            }
            .padding(.trailing, DS.Sidebar.trailing)
            .padding(.bottom, DS.Space.xxs)
            .contentShape(.rect)
            .trackHover($isHovered)
            .contextMenu(menuItems: menu)

            if isExpanded {
                LazyVStack(alignment: .leading, spacing: 0, content: content)
                    .transition(.opacity)
            }
        }
        .padding(.top, isFirst ? DS.Space.md : DS.Sidebar.headerTop)
    }
}

#if DEBUG
#Preview("All in view project headers - Expanded, collapsed and filtered") {
    DSPreviewPair {
        VStack(spacing: DS.Space.md) {
            AllInViewProjectGroup(
                name: "native", isExpanded: .constant(true), taskCount: 6,
                activity: ProjectActivity(), note: nil, onNewTask: {}
            ) {
                Button("Project Settings…") {}
            } content: {
                Text("Tasks")
            }
            AllInViewProjectGroup(
                name: "a-project-with-a-long-folder-name", isExpanded: .constant(false), taskCount: 12,
                activity: ProjectActivity(needsYou: 1, working: 2), note: nil, onNewTask: {}
            ) {
                Button("Project Settings…") {}
            } content: {
                EmptyView()
            }
            AllInViewProjectGroup(
                name: "sample", isExpanded: .constant(false), taskCount: 0,
                activity: ProjectActivity(), note: "No matching tasks", onNewTask: {}
            ) {
                Button("Project Settings…") {}
            } content: {
                EmptyView()
            }
        }
        .frame(width: DS.Window.sidebarMinWidth)
    }
}
#endif
