import NativeCommands
import NativePolicy
import Search
import SwiftUI

extension SettingsPane.ID {
    static let search = Self("search")
}

extension SettingsPane {
    /// Settings › Search: past sessions, excluded projects and the index itself.
    static func search(_ center: TranscriptSearchCenter) -> SettingsPane {
        SettingsPane(
            id: .search,
            title: "Search",
            systemImage: "magnifyingglass",
            group: .personal,
            order: 18,
            keywords: ["find", "index", "history", "transcripts", "privacy", "exclude"],
            searchEntries: {
                [
                    SettingsSearchEntry(
                        id: TranscriptSearchSettingsPage.historyRow, title: "Include agents' past tasks",
                        keywords: ["history", "backfill"], plainly: .history),
                    SettingsSearchEntry(
                        id: TranscriptSearchSettingsPage.excludedRow, title: "Excluded projects",
                        keywords: ["privacy", "exclude", "ignore"]),
                    SettingsSearchEntry(
                        id: TranscriptSearchSettingsPage.indexRow, title: "Clear search index",
                        keywords: ["delete", "reset", "privacy"], plainly: .init(title: "Search index")),
                ]
            },
            content: { TranscriptSearchSettingsPage(center: center) }
        )
    }
}

struct TranscriptSearchSettingsPage: View {
    static let historyRow = SettingsRowID("search.history")
    static let excludedRow = SettingsRowID("search.excluded")
    static let indexRow = SettingsRowID("search.index")
    static let retentionRow = SettingsRowID("search.retention")

    @Bindable var center: TranscriptSearchCenter

    @Environment(AppModel.self) private var model
    @State private var isClearing = false

    var body: some View {
        SettingsPage {
            SettingsHeader(
                "Search",
                description: Text(
                    CommandRegistry.shared.help("Find any task by what was said in it", for: .searchShow)
                        + ". The index lives on this Mac and is never sent anywhere."
                ), plainly: .init(title: "Search", description: "Which tasks Native can find for you."))
            SettingsRowGroup {
                SettingsRow(
                    id: Self.historyRow,
                    "Include agents' past tasks", plainly: .history,
                    description: Text(
                        "Also index the tasks your agents keep in their own history, including ones started outside Native. Read only; nothing there changes."
                    ),
                    detail: indexingDetail.map(Text.init)
                ) {
                    SettingsSwitch("Include agents' past tasks", isOn: $center.includesAgentHistory)
                }
                if let days = PolicyCenter.shared.policy.searchRetentionDays {
                    SettingsRow(
                        id: Self.retentionRow,
                        "Keep tasks for",
                        description: Text(
                            "Tasks with no activity for longer are left out of search and removed from the index.")
                    ) {
                        SettingsValue(days == 1 ? "1 day" : "\(days) days")
                    }
                    .settingsManaged(by: .searchRetentionDays)
                }
                SettingsRow(
                    id: Self.indexRow,
                    "Search index",
                    description: Text(indexDescription)
                ) {
                    Button(isClearing ? "Clearing…" : "Clear Index") {
                        isClearing = true
                        Task {
                            await center.clearIndex()
                            isClearing = false
                        }
                    }
                    .disabled(isClearing)
                }
            }
            SettingsSubheading(
                "Excluded projects",
                note: "Tasks in these folders are never indexed, and are removed from the index.")
            SettingsRowGroup {
                ForEach(center.excludedFolders, id: \.self) { folder in
                    SettingsRow(URL(filePath: folder).lastPathComponent, description: Text(folder)) {
                        Button("Include") {
                            Task { await center.include(folder) }
                        }
                    }
                }
                SettingsRow(
                    id: Self.excludedRow,
                    center.excludedFolders.isEmpty ? "No excluded projects" : "Exclude another project",
                    description: Text("Keep a project's tasks out of search, such as one with sensitive work."),
                    detail: excludeUnavailableReason.map(Text.init)
                ) {
                    Menu("Exclude Project") {
                        ForEach(model.projects.all.filter { !center.excludedFolders.contains($0.path) }) { project in
                            Button(project.name) {
                                Task { await center.exclude(project.path) }
                            }
                        }
                    }
                    .menuStyle(.button)
                    .menuIndicator(.hidden)
                    .disabled(model.projects.all.allSatisfy { center.excludedFolders.contains($0.path) })
                }
            }
        }
    }

    /// Why there's nothing to exclude, when the button can't open its menu.
    private var excludeUnavailableReason: String? {
        if model.projects.all.isEmpty { return "Add a project to Native first." }
        if model.projects.all.allSatisfy({ center.excludedFolders.contains($0.path) }) {
            return "Every project is already excluded."
        }
        return nil
    }

    private var indexDescription: String {
        guard let statistics = center.statistics else {
            return "Native rebuilds it from your tasks whenever it's cleared."
        }
        let size = DSFormat.memory(UInt64(max(statistics.bytes, 0)))
        return
            "\(statistics.sessions) tasks, \(size) on disk. Clearing it forgets everything indexed; Native rebuilds it from your tasks."
    }

    private var indexingDetail: String? {
        switch center.indexing {
        case .idle: nil
        case .indexing(let done, let total): "Indexing: \(done) of \(total) tasks."
        case .paused(let done, let total):
            "Paused on battery at \(done) of \(total); continues when your Mac is plugged in."
        }
    }
}
