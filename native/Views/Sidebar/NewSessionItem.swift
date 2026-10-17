import SwiftUI

/// The sidebar's first navigation item (Factory's "New session"): starts a session in the current
/// project with the default agent, with a menu at its end for picking another agent.
struct NewSessionItem: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        SidebarNavItem("New Session", systemImage: "plus", shortcut: "⌘N") {
            Task { await model.newSession() }
        } accessory: {
            SidebarRowMenu(label: "New Session With") {
                Section("New Session With") {
                    ForEach(model.agents, id: \.agent.id) { runtime in
                        Button(runtime.agent.displayName, systemImage: runtime.agent.symbolName) {
                            Task { await model.newSession(with: runtime.agent.id) }
                        }
                        .disabled(!model.canCreateSession(with: runtime.agent.id))
                    }
                }
            }
        }
        .disabled(model.projects.all.isEmpty || !model.agents.contains { model.canCreateSession(with: $0.agent.id) })
        .help(help)
    }

    private var help: String {
        let agent = model.defaultAgent.map { "\($0.displayName) " } ?? ""
        let project = model.currentProject.map { " in \($0.name)" } ?? ""
        return "New \(agent)Session\(project) (⌘N)"
    }
}
