/// Actions another feature offers on a sidebar task, shown as one submenu of its row's context
/// menu ("Pull Request") and as VoiceOver actions on the row. Data rather than a view, so the row
/// stays free of the feature; the app wires it through `SidebarTaskInsights`.
struct SidebarTaskMenu {
    struct Item: Identifiable {
        /// The menu item's title, within the submenu: "Open on GitHub".
        let title: String
        /// What VoiceOver offers on the row, where the submenu's title isn't there to say what it
        /// acts on: "Open Pull Request on GitHub".
        let spokenTitle: String
        let perform: @MainActor () -> Void

        var id: String { title }
    }

    let title: String
    /// What the row's VoiceOver label adds about it: "pull request #12, open, checks failing".
    let spokenSummary: String
    let items: [Item]
}
