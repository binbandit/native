import SwiftUI

/// Sample data for the gallery and previews, so components never need app models to render.
enum GalleryFixtures {
    struct SampleTask: Identifiable {
        let id: String
        let title: String
        let status: TaskStatus
        var isUnread = false
        var subtitle: String?
        var age: TimeInterval?
        var diff: (added: Int, removed: Int)?
        var badge: TaskBadge?
    }

    static let tasks: [SampleTask] = [
        SampleTask(id: "tokens", title: "Design system tokens", status: .working, age: 90),
        SampleTask(id: "focus", title: "Fix composer focus ring", status: .needsPermission, isUnread: true, badge: .attention("Approve")),
        SampleTask(id: "polish", title: "Sidebar polish", status: .done, isUnread: true, diff: (added: 128, removed: 14), badge: .dot),
        SampleTask(id: "flaky", title: "Investigate flaky test", status: .failed, subtitle: "Codex · fix/flaky-ui-test", age: 3600 * 26),
    ]
}

extension TaskRow where Leading == EmptyView, Accessory == EmptyView {
    /// A row for a sample task.
    init(_ task: GalleryFixtures.SampleTask, isSelected: Bool = false, action: @escaping () -> Void) {
        self.init(
            title: task.title,
            status: task.status,
            isSelected: isSelected,
            isUnread: task.isUnread,
            subtitle: task.subtitle,
            date: task.age.map { Date.now.addingTimeInterval(-$0) },
            diff: task.diff,
            badge: task.badge,
            action: action,
            onArchive: {}
        )
    }
}

/// Shows a preview's content in light and dark side by side, each on the content background.
struct DSPreviewPair<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
                content
                    .padding(DS.Space.xl)
                    .frame(maxHeight: .infinity)
                    .background(.dsBackground)
                    .environment(\.colorScheme, scheme)
            }
        }
        .fixedSize()
    }
}
