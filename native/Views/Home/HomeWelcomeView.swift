import SwiftUI

/// Home before any project is open. Adding a project is the one thing to do, so it's the one card,
/// and the quiet line under it says which agents will work there.
public struct HomeWelcomeView<AgentID: Hashable>: View {
    let agents: [HomeAgent<AgentID>]
    /// The Open Folder shortcut, shown on the card.
    let addProjectShortcut: KeyboardShortcut?
    let onAddProject: () -> Void

    public init(agents: [HomeAgent<AgentID>], addProjectShortcut: KeyboardShortcut?, onAddProject: @escaping () -> Void)
    {
        self.agents = agents
        self.addProjectShortcut = addProjectShortcut
        self.onAddProject = onAddProject
    }

    public var body: some View {
        HomePage {
            HomeActionCard(
                "Add a project", systemImage: "folder.badge.plus", detail: "Choose a folder to work in",
                action: onAddProject
            ) {
                if let addProjectShortcut {
                    Kbd(addProjectShortcut)
                }
            }
            .help(addProjectShortcut.map { "Open Folder… (\($0.displayString))" } ?? "Open Folder…")
        } footer: {
            if !agents.isEmpty {
                HomeAgentList(agents: agents)
            }
        } content: {
            EmptyView()
        }
    }
}
