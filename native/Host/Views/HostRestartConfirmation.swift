import NativeHostProtocol
import SwiftUI

extension View {
    /// Asks before restarting the background host while tasks work, naming the ones a restart now
    /// would interrupt (`DurableHost.interruptedByRestart`). Waiting is the default: the host
    /// restarts by itself once they finish.
    @ViewBuilder
    func hostRestartConfirmation(_ host: DurableHost?) -> some View {
        if let host {
            modifier(HostRestartConfirmation(host: host))
        } else {
            self
        }
    }
}

private struct HostRestartConfirmation: ViewModifier {
    let host: DurableHost

    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        let names = host.interruptedByRestart.map(title)
        content.confirmationDialog(
            "Restart the background host?",
            isPresented: Binding(
                get: { host.manualRestart.state == .confirming },
                set: { if !$0 { host.cancelHostRestart() } }
            ), titleVisibility: .visible
        ) {
            Button("Cancel", role: .cancel) { host.cancelHostRestart() }
            if !names.isEmpty {
                Button(Self.waitLabel(for: names.count)) {
                    Task { await host.confirmHostRestart(whenIdle: true) }
                }
                .keyboardShortcut(.defaultAction)
                Button(Self.restartLabel(interrupting: names.count), role: .destructive) {
                    Task { await host.confirmHostRestart() }
                }
            } else {
                Button("Restart") { Task { await host.confirmHostRestart() } }
                    .keyboardShortcut(.defaultAction)
            }
        } message: {
            Text(Self.message(interrupting: names))
        }
    }

    /// The title the sidebar shows for the task, else the agent's.
    private func title(_ summary: HostSessionSummary) -> String {
        let listed = summary.agentSessionID.flatMap { id in
            let key = SessionKey(agent: AgentDefinition.ID(rawValue: summary.agentID), id: id)
            return model.sessionList.first { $0.id == key }
        }
        return listed.map(model.title(for:)) ?? summary.title ?? "New Task"
    }

    private static func waitLabel(for count: Int) -> String {
        switch count {
        case 0: "Cancel"
        case 1: "Wait Until It Finishes"
        default: "Wait Until They Finish"
        }
    }

    private static func restartLabel(interrupting count: Int) -> String {
        switch count {
        case 0: "Restart Now"
        case 1: "Interrupt 1 Task and Restart"
        default: "Interrupt \(count) Tasks and Restart"
        }
    }

    /// Names at most three tasks. The tasks can finish while it's open, leaving nothing to interrupt.
    private static func message(interrupting names: [String]) -> String {
        guard !names.isEmpty else { return "Your tasks will reconnect." }
        let shown = names.prefix(3).map { "“\($0)”" }
        let more = names.count > shown.count ? ["\(names.count - shown.count) more"] : []
        let tasks = (shown + more).formatted(.list(type: .and))
        return names.count == 1
            ? "Restarting now interrupts \(tasks). A command it's running stops, and its turn resumes right after. If you wait, the host restarts by itself once it finishes."
            : "Restarting now interrupts \(tasks). Commands they're running stop, and their turns resume right after. If you wait, the host restarts by itself once they finish."
    }
}
