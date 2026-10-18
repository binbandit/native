import ACP
import Foundation

/// Automations as a plugin: tasks that start themselves on a schedule or an event. Off until the
/// user turns it on or makes their first automation (Minimal by default). It shares the center with
/// goals and workflows, and hears turns end so "a task finishes" can trigger.
struct AutomationsPlugin: NativePlugin {
    let manifest = PluginManifest(
        id: "automations",
        name: "Automations",
        description:
            "Starts tasks on their own: on a schedule, when a pull request changes or CI fails, or when a task finishes."
    )

    let center: AutomationCenter

    var isEnabledByDefault: Bool { false }

    func handle(_ event: SessionEvent) async {
        if case .turnEnded(let context, .endTurn) = event {
            center.taskTurnEnded(context)
        }
    }
}
