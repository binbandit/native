import SessionTools
import SwiftUI
import Terminal

/// The terminal as a session tool: every shell and every run a tab of its own in the workbench by
/// default, no fact of its own (a run says what it's doing through Run), and ⌃` keeps working.
@MainActor
enum SessionTerminalTool {
    static func contribution(terminals: TerminalStore) -> SessionToolContribution {
        let panel = { (context: SessionToolContext) in terminals.panel(for: context.session) }
        return SessionToolContribution(
            spec: SessionToolSpec(id: .terminal, places: [.workbench, .side, .fact, .off], defaultPlace: .workbench),
            title: "Terminal", systemImage: "apple.terminal",
            hasContent: { !panel($0).tabs.isEmpty },
            pane: { context in AnyView(SessionTerminalPane(panel: panel(context), store: terminals)) },
            tabs: { context in
                let panel = panel(context)
                return panel.tabs.tabs.map { tab in
                    SessionToolTabItem(
                        id: tab.id.uuidString, title: panel.tabs.label(of: tab),
                        systemImage: tab.job == nil ? "apple.terminal" : "play", accessory: tab.job.flatMap(accessory),
                        isSelected: tab.id == panel.tabs.selectedID,
                        select: {
                            panel.select(tab.id)
                            context.open(.terminal)
                        },
                        close: { panel.requestClose(tab.id) })
                }
            },
            newTab: { context in
                panel(context).newTab()
                context.open(.terminal)
            },
            stripAccessory: { context in
                let panel = panel(context)
                guard let tab = panel.tabs.selected, let job = tab.job, job.isRunning else { return nil }
                return AnyView(TerminalJobControls(job: job) { panel.stopJob(in: tab.id) })
            },
            companion: { context in
                AnyView(SessionTerminalCompanion(panel: panel(context), store: terminals, screen: context.screen))
            })
    }

    /// A run's tab says how it's going.
    private static func accessory(_ job: TerminalJob) -> SessionToolFact.Accessory? {
        if job.isRunning { return .working }
        return job.outcome.map(ProjectActionRunState.finished)?.hasFailed == true ? .failed : nil
    }
}
