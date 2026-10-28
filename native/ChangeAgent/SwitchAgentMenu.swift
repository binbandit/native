import ACP
import SwiftUI

/// The task's own host supplies the same choices as the composer.
struct SwitchAgentMenu: View {
    let model: AppModel
    let menu: CommandMenuContext

    var body: some View {
        Menu("Switch Agent") {
            if let session = menu.context.session {
                let groups = AgentModelGroups(model.composerAgentModels(for: session), agent: \.agent)
                ForEach(groups.groups) { group in
                    if let agent = group.models.first {
                        Toggle(
                            agent.agentName,
                            isOn: Binding(
                                get: { agent.agent == session.agent.id },
                                set: { _ in
                                    model.switchAgent(
                                        to: agent.agent, for: session, undoManager: menu.context.undoManager)
                                })
                        )
                        .disabled(agent.unavailable != nil || session.modelChange?.isPending == true)
                        .help(agent.unavailable ?? "Continue this task with \(agent.agentName)")
                    }
                }
                Divider()
            }
            CommandMenuItem(.sessionChangeAgent, in: menu, title: "Choose Agent…")
        }
    }
}

#if DEBUG
#Preview("Switch Agent - Task menu") {
    let app = ChangeAgentPreviewFixtures.app()
    let registry = CommandRegistry(defaults: PreviewUserDefaults())
    registry.register([.changeAgent(model: app)])
    return DSPreviewPair {
        SwitchAgentMenu(
            model: app,
            menu: CommandMenuContext(
                registry: registry, context: CommandContext(session: ChangeAgentPreviewFixtures.source(in: app))))
    }
}
#endif
