import SwiftUI

/// A project header with its tasks underneath, collapsible (the reference app `RepoGroup`: 4pt between
/// task rows, 2pt above and 4pt below the header).
public struct ProjectGroup<MenuContent: View, Content: View>: View {
    let name: String
    let icon: ProjectIcon
    @Binding var isExpanded: Bool
    let taskCount: Int?
    let onNewTask: (() -> Void)?
    let menu: MenuContent
    let content: Content

    public init(
        name: String,
        icon: ProjectIcon = .initial,
        isExpanded: Binding<Bool>,
        taskCount: Int? = nil,
        onNewTask: (() -> Void)? = nil,
        @ViewBuilder menu: () -> MenuContent,
        @ViewBuilder content: () -> Content
    ) {
        self.name = name
        self.icon = icon
        self._isExpanded = isExpanded
        self.taskCount = taskCount
        self.onNewTask = onNewTask
        self.menu = menu()
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProjectRow(
                name: name,
                icon: icon,
                isExpanded: isExpanded,
                taskCount: taskCount,
                onToggle: { withAnimation(.dsDisclosure) { isExpanded.toggle() } },
                onNewTask: onNewTask
            ) {
                menu
            }
            .padding(.top, DS.Space.xxs)
            .padding(.bottom, DS.Space.xs)

            if isExpanded {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    content
                }
                .transition(.opacity)
            }
        }
    }
}

extension ProjectGroup where MenuContent == EmptyView {
    public init(
        name: String,
        icon: ProjectIcon = .initial,
        isExpanded: Binding<Bool>,
        taskCount: Int? = nil,
        onNewTask: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            name: name, icon: icon, isExpanded: isExpanded, taskCount: taskCount, onNewTask: onNewTask,
            menu: { EmptyView() }, content: content)
    }
}

#Preview("Project group") {
    @Previewable @State var isExpanded = true
    DSPreviewPair {
        ProjectGroup(name: "native", isExpanded: $isExpanded, taskCount: GalleryFixtures.tasks.count, onNewTask: {}) {
            ForEach(GalleryFixtures.tasks) { task in
                TaskRow(task, action: {})
            }
        }
        .frame(width: 244)
    }
}
