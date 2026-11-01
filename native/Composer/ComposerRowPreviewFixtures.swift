#if DEBUG
import SwiftUI

enum ComposerRowPreviewFixtures {
    static var state: ComposerRowState {
        ComposerRowState(
            agentLabel: "Claude Code · Sonnet",
            agents: [
                .init(
                    id: "claude-code", name: "Claude Code",
                    models: [
                        .init(id: "sonnet", title: "Sonnet", isSelected: true),
                        .init(id: "opus", title: "Opus"), .init(id: "haiku", title: "Haiku"),
                    ]),
                .init(
                    id: "codex", name: "Codex",
                    models: [
                        .init(id: "gpt", title: "GPT-5"), .init(id: "gpt-mini", title: "GPT-5 mini"),
                    ]),
                .init(
                    id: "copilot", name: "Copilot",
                    models: [
                        .init(id: "copilot-auto", title: "Auto"), .init(id: "copilot-sonnet", title: "Sonnet"),
                    ]),
                .init(
                    id: "plugin", name: "Project agent",
                    models: [
                        .init(id: "plugin-default", title: "Default"),
                        .init(id: "plugin-load", title: "Load models…", unavailable: "Sign in required"),
                    ]),
            ],
            effort: [
                .init(id: "low", title: "Low"), .init(id: "medium", title: "Medium", isSelected: true),
                .init(id: "high", title: "High"),
            ],
            modes: [
                .init(
                    id: "ask-first", title: "Ask first",
                    detail: "Asks before edits and commands, subject to your permission rules."),
                .init(
                    id: "accept-edits", title: "Accept edits", detail: "Allows file edits. Asks before other actions."),
                .init(
                    id: "auto", title: "Auto",
                    detail: "Reviews actions automatically and asks when an action needs you."),
                .init(
                    id: "full-access", title: "Full access",
                    detail: "The agent can run any command and change any file without asking.", isSelected: true),
            ],
            defaultModeID: "full-access",
            locations: [
                .init(
                    id: "project", title: "In my folder", detail: "Use the project folder as it is.", isSelected: true),
                .init(
                    id: "branch", title: "On a new branch",
                    detail: "Use a separate copy with an automatically named branch."),
            ])
    }

    static func row(_ state: ComposerRowState = state, width: CGFloat = DS.ComposerRow.previewWidth) -> some View {
        ComposerBottomRow(state: state, actions: .init(), openMenu: .constant(nil))
            .frame(width: width)
            .background(.dsSurface, in: .rect(cornerRadius: DS.Radius.panel))
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.panel)
                    .strokeBorder(.dsBorder, lineWidth: DS.ComposerRow.borderWidth)
            }
    }

    static func agentMenu() -> some View {
        ComposerAgentModelMenu(
            agents: state.agents, effort: state.effort, chooseModel: { _ in }, chooseEffort: { _ in }, close: {})
    }
}

#Preview("Composer row - Quiet default, at half, above half, Stop and Stopping") {
    DSPreviewPair {
        VStack(spacing: DS.Space.lg) {
            ComposerRowPreviewFixtures.row()
            ComposerRowPreviewFixtures.row(
                {
                    var state = ComposerRowPreviewFixtures.state
                    state.locations = []; state.contextFraction = 0.5
                    return state
                }())
            ComposerRowPreviewFixtures.row(
                {
                    var state = ComposerRowPreviewFixtures.state
                    state.locations = []; state.contextFraction = 0.51
                    return state
                }())
            ComposerRowPreviewFixtures.row(
                {
                    var state = ComposerRowPreviewFixtures.state
                    state.locations = []; state.contextFraction = 0.96; state.isWorking = true
                    return state
                }())
            ComposerRowPreviewFixtures.row(
                {
                    var state = ComposerRowPreviewFixtures.state
                    state.locations = []; state.isWorking = true; state.isStopping = true
                    return state
                }())
        }
    }
}

#Preview("Composer row - Every removable mode, long name and iPad split width") {
    DSPreviewPair {
        VStack(spacing: DS.Space.lg) {
            ForEach(["Ask first", "Accept edits", "Auto"], id: \.self) { mode in
                ComposerRowPreviewFixtures.row(
                    {
                        var state = ComposerRowPreviewFixtures.state
                        state.modeLabel = mode; state.isDefaultMode = false
                        state.agentLabel =
                            "Project's custom coding agent · Very long model name with a deployment suffix"
                        return state
                    }(), width: DS.ComposerRow.narrowPreviewWidth)
            }
            ComposerRowPreviewFixtures.row(
                {
                    var state = ComposerRowPreviewFixtures.state
                    state.locationLabel = "On a new branch"
                    state.disabledReason = "Write a message to send"
                    return state
                }(), width: DS.ComposerRow.narrowPreviewWidth)
        }
    }
}

#Preview("Composer menus - Agent, Mode and Where open") {
    DSPreviewPair {
        HStack(alignment: .top, spacing: DS.Space.lg) {
            ComposerRowPreviewFixtures.agentMenu()
            VStack(spacing: DS.Space.lg) {
                ComposerModeMenu(choices: ComposerRowPreviewFixtures.state.modes) { _ in }
                ComposerWhereMenu(choices: ComposerRowPreviewFixtures.state.locations) { _ in }
            }
        }
    }
}

#Preview("Composer menus - Empty catalog, long name, sign-in and managed mode") {
    DSPreviewPair {
        HStack(alignment: .top, spacing: DS.Space.lg) {
            VStack(spacing: DS.Space.lg) {
                ComposerAgentModelMenu(agents: [], effort: [], chooseModel: { _ in }, chooseEffort: { _ in }, close: {})
                ComposerModeMenu(
                    choices: ComposerRowPreviewFixtures.state.modes.map {
                        var choice = $0
                        if choice.id == "full-access" { choice.unavailable = "Managed by your organization" }
                        return choice
                    }
                ) { _ in }
            }
            ComposerAgentModelMenu(
                agents: [
                    .init(
                        id: "plugin", name: "Project agent",
                        models: [
                            .init(
                                id: "deployment", title: "Custom model with a long deployment name and regional suffix",
                                isSelected: true),
                            .init(id: "load", title: "Load models…", unavailable: "Sign in required"),
                        ])
                ], effort: [], chooseModel: { _ in }, chooseEffort: { _ in }, close: {})
        }
    }
}

#Preview("Composer agent search - Agent match and no matches") {
    DSPreviewPair {
        HStack(alignment: .top, spacing: DS.Space.lg) {
            ForEach(["Codex", "No such model"], id: \.self) { query in
                ComposerAgentModelMenu(
                    agents: ComposerRowPreviewFixtures.state.agents, effort: ComposerRowPreviewFixtures.state.effort,
                    query: query, chooseModel: { _ in }, chooseEffort: { _ in }, close: {})
            }
        }
    }
}

#Preview("Composer agent menu - Short list and waiting choice") {
    DSPreviewPair {
        HStack(alignment: .top, spacing: DS.Space.lg) {
            ComposerAgentModelMenu(
                agents: Array(ComposerRowPreviewFixtures.state.agents.prefix(1)),
                effort: ComposerRowPreviewFixtures.state.effort,
                chooseModel: { _ in }, chooseEffort: { _ in }, close: {})
            ComposerAgentModelMenu(
                agents: ComposerRowPreviewFixtures.state.agents, effort: ComposerRowPreviewFixtures.state.effort,
                notice: "Next model: Opus · Claude Code. Waiting for this turn to finish.",
                chooseModel: { _ in }, chooseEffort: { _ in }, close: {})
        }
    }
}
#endif
