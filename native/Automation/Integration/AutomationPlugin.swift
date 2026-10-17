import Foundation

/// Goals and workflows as a plugin: it hears every session's turns, which is all the goal loop and
/// the workflow runner need to drive agents. Keep one instance, and hand its `center` to the views.
struct AutomationPlugin: NativePlugin {
    let manifest = PluginManifest(
        id: "automation",
        name: "Goals and Workflows",
        description: "Keeps an agent working toward a goal across turns, and runs multi-agent workflows such as plan, implement and review."
    )

    let center = AutomationCenter()

    func handle(_ event: SessionEvent) async {
        await center.handle(event)
    }
}
