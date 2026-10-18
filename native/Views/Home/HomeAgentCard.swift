import SwiftUI

/// An agent's card: starts a task with it, or, while it can't, says why and offers what fixes it.
struct HomeAgentCard<ID: Hashable>: View {
    let agent: HomeAgent<ID>
    /// Another card is starting a task; tasks start one at a time.
    let isBusy: Bool
    let onNewTask: () -> Void

    var body: some View {
        HomeActionCard(
            title, systemImage: agent.symbolName, agent: agent.agent, detail: detail, isDetailUrgent: remedy != nil
        ) {
            if let remedy {
                remedy.action()
            } else {
                onNewTask()
            }
        } accessory: {
            switch agent.availability {
            case .starting, .creatingTask:
                DotGridLoader(pattern: .settingUp)
                    .frame(width: HomeLayout.cardGlyphSlot, height: HomeLayout.cardGlyphSlot)
                    .foregroundStyle(.dsTextTertiary)
            case .available:
                if let shortcut = agent.shortcut {
                    Kbd(shortcut)
                }
            case .unavailable:
                EmptyView()
            }
        }
        .disabled(!isActionable)
        .help(help)
    }

    /// The fix on offer, while the agent can't start tasks.
    private var remedy: HomeAgentRemedy? {
        if case .unavailable = agent.availability { agent.remedy } else { nil }
    }

    private var isActionable: Bool {
        switch agent.availability {
        case .available: !isBusy
        case .unavailable: remedy != nil
        case .starting, .creatingTask: false
        }
    }

    private var title: String {
        remedy?.title ?? "New \(agent.name) task"
    }

    private var detail: String? {
        switch agent.availability {
        case .available: nil
        case .starting: "Starting…"
        case .creatingTask: "Starting a task…"
        case .unavailable(let status): status
        }
    }

    private var help: String {
        if let remedy, case .unavailable(let status) = agent.availability {
            return "\(agent.name): \(status). \(remedy.title)."
        }
        return agent.shortcut.map { "New \(agent.name) Task (\($0.displayString))" } ?? "New \(agent.name) Task"
    }
}
