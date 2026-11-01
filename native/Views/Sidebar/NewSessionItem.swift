import NativeCommands
import SwiftUI

/// The sidebar's first navigation item, "New Session": starts a session in the current
/// project with the default agent, with a menu at its end for picking another agent.
struct NewSessionItem: View {
    @Environment(AppModel.self) private var model
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        SidebarNavItem(
            "New Task", systemImage: "plus",
            shortcut: CommandRegistry.shared.shortcut(for: .sessionNew)?.displayString
        ) {
            Task { await model.newSession() }
        } accessory: {
            SidebarRowMenu(label: "New Task With") {
                // Menus only show item icons when the content asks for them.
                Group {
                    Section("New Task With") {
                        ForEach(model.agents, id: \.agent.id) { runtime in
                            Button {
                                Task { await model.newSession(with: runtime.agent.id) }
                            } label: {
                                Label {
                                    Text(runtime.agent.displayName)
                                } icon: {
                                    // Menus draw only an `Image`.
                                    AgentIconStore.shared.image(
                                        for: runtime.agent, size: DS.Size.rowLeading, scale: displayScale,
                                        colorScheme: colorScheme)
                                }
                            }
                            .disabled(!model.canCreateSession(with: runtime.agent.id))
                        }
                    }
                    if !model.agentsToAdd.isEmpty {
                        Divider()
                        Button("Add Agent…", systemImage: "plus") { model.isAddingAgent = true }
                    }
                }
                .labelStyle(.titleAndIcon)
            }
        }
        .disabled(
            model.agentStartupFailure == nil
                && !model.agents.contains { model.canCreateSession(with: $0.agent.id) }
        )
    }
}

#if DEBUG
#Preview("New task item") {
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            NewSessionItem()
                .sidebarPreviewEnvironment(AppModel.preview())
            // A project is optional.
            NewSessionItem()
                .sidebarPreviewEnvironment(AppModel.preview(.empty))
        }
        .frame(width: DS.Size.sidebarWidth)
    }
}
#endif
