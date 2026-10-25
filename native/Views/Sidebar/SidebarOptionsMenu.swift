import SwiftUI
import TaskList

/// The menu bar and the list expose the same persisted additions.
struct SidebarOptionsMenu: View {
    let preferences: TaskSidebarPreferences

    var body: some View {
        Section("Show in Sidebar") {
            ForEach(TaskSidebarPreferences.Fact.allCases, id: \.self) { fact in
                Toggle(
                    fact.title,
                    isOn: Binding(
                        get: { preferences.shows(fact) },
                        set: { preferences.set(fact, shown: $0) }))
            }
        }
        Picker(
            "Fold Tasks Older Than",
            selection: Binding(
                get: { preferences.foldAfter }, set: preferences.setFoldAfter)
        ) {
            ForEach(TaskDayFolding.Interval.allCases, id: \.self) { interval in
                Text(interval.title).tag(interval)
            }
        }
        .pickerStyle(.menu)
    }
}

#if DEBUG
#Preview("Sidebar options - Calm default") {
    DSPreviewPair {
        Menu("Sidebar") { SidebarOptionsMenu(preferences: TaskSidebarPreferences(defaults: PreviewUserDefaults())) }
    }
}
#endif
