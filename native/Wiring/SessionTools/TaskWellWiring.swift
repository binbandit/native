import SwiftUI

/// Adapts the existing task tools to the well without making a second terminal, action menu,
/// approval or review surface. Later tool contributions can replace these adapters in one place.
struct TaskWellWiring: View {
    let session: SessionModel
    let tools: SessionToolsScreenModel
    let location: String
    let turnChanges: TurnChangesActions?
    let openSubagents: () -> Void
    @Environment(AppModel.self) private var app
    @Environment(TerminalStore.self) private var terminal
    @Environment(ProjectActionRunner.self) private var actions

    var body: some View {
        TaskWellToolbar(session: session, tools: tools, location: location, turnChanges: turnChanges, detail: detail) {
            if let target = ProjectActionsWiring.target(for: session, model: app) {
                ProjectActionsMenuContent(target: target)
            }
        }
        .onAppear {
            tools.hasWell = true
            tools.wellToolAvailable = available
            tools.wellToolAction = perform
        }
        .onDisappear {
            tools.hasWell = false
            tools.wellToolAvailable = { _ in false }
            tools.wellToolAction = { _ in }
        }
        .task(id: session.key) {
            if let target = ProjectActionsWiring.target(for: session, model: app) {
                actions.store.refresh(target.project)
            }
        }
    }

    private func available(_ tool: TaskWellTool) -> Bool {
        switch tool {
        case .changes: tools.registry.place(of: .changes) != .off
        case .terminal: true
        case .dev: ProjectActionsWiring.target(for: session, model: app) != nil
        case .subagents: session.hasSubagents
        case .pullRequest:
            CommandRegistry.shared.command(.pullRequestOpenForTask)?.isAvailable(CommandContext(session: session))
                == true
        }
    }

    private func perform(_ tool: TaskWellTool) {
        switch tool {
        case .changes: tools.toggle(.changes)
        case .terminal: terminal.toggle(for: session)
        case .dev: break
        case .subagents: openSubagents()
        case .pullRequest: CommandRegistry.shared.perform(.pullRequestOpenForTask, in: CommandContext(session: session))
        }
    }

    private func detail(_ tool: TaskWellTool) -> String {
        switch tool {
        case .changes:
            guard let contribution = tools.registry.tool(.changes) else { return "" }
            return contribution.fact(SessionToolContext(session: session, screen: tools, tool: .changes))?.text ?? ""
        case .terminal: return terminal.panel(for: session).isVisible ? "Open" : ""
        case .dev:
            guard let target = ProjectActionsWiring.target(for: session, model: app) else { return "" }
            return actions.running(in: target).map(\.name).joined(separator: ", ")
        case .subagents: return "\(session.state.subagents.count)"
        case .pullRequest: return ""
        }
    }
}

#if DEBUG
// The adapter refreshes project actions. Preview only its inert presentation, without file reads.
#Preview("Well - Existing tool adapters") {
    let tools = SessionToolsScreenModel()
    tools.wellToolAvailable = { $0 != .subagents && $0 != .pullRequest }
    return DSPreviewPair {
        TaskWellToolsPanel(content: TaskWellPreviewFixtures.states[0], location: "native · main", tools: tools) {
            $0 == .changes ? "3 files" : ""
        } dev: {
            EmptyView()
        }
    }
}
#endif
