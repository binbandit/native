import ProjectActions
import SessionTools
import SwiftUI
import Terminal

/// The project's actions as a session tool: "Dev :3000" under the title while an action runs,
/// "Test failed" after the last run failed, and the run's output in the terminal from either. It
/// has no pane of its own: a run is a terminal tab.
@MainActor
enum SessionRunTool {
    static func contribution(
        model: AppModel, runner: ProjectActionRunner, terminals: TerminalStore
    )
        -> SessionToolContribution
    {
        let target = { (context: SessionToolContext) in ProjectActionsWiring.target(for: context.session, model: model)
        }
        return SessionToolContribution(
            spec: SessionToolSpec(id: .run, places: [.fact, .off], defaultPlace: .fact),
            title: "Run", systemImage: "play",
            fact: { context in
                guard let target = target(context) else { return nil }
                let running = runner.running(in: target)
                if let first = running.first {
                    let port = port(in: first.command).map { " :\($0)" } ?? ""
                    return SessionToolFact(
                        text: running.count == 1 ? first.name + port : "\(running.count) running", accessory: .working)
                }
                guard let last = runner.store.lastRunAction(in: target.project),
                    runner.state(of: last, in: target)?.hasFailed == true
                else { return nil }
                return SessionToolFact(text: "\(last.name) failed", accessory: .failed)
            },
            perform: { context in
                guard let target = target(context) else { return }
                let panel = terminals.panel(for: context.session)
                let shown = runner.running(in: target).first ?? runner.store.lastRunAction(in: target.project)
                if let shown, let tab = panel.tabs.tab(forJob: shown.id.rawValue) {
                    panel.select(tab.id)
                }
                context.open(.terminal)
            },
            companion: { context in
                // The project's actions are read when a task shows, as the Run menu reads them, so a
                // run's fact knows them.
                AnyView(
                    Color.clear.task(id: target(context)?.project.id) {
                        if let project = target(context)?.project { runner.store.refresh(project) }
                    })
            })
    }

    /// The port a dev server's command names, for its fact; nil when the command doesn't say.
    private static func port(in command: String) -> Substring? {
        command.firstMatch(of: /(?:--port[= ]|-p |PORT=|localhost:|127\.0\.0\.1:|http\.server )(\d{2,5})\b/)?.1
    }
}
