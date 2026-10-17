#if EXPEDITIONS_WIP
import Foundation
import NativeExpeditions

/// Expeditions as a plugin: it hears every session's turns, which is all the runner needs to drive
/// a crew. Off by default, so a new install shows nothing of it until the user starts one.
struct ExpeditionsPlugin: NativePlugin {
    let manifest = PluginManifest(
        id: "expeditions",
        name: "Expeditions",
        description: "A crew of agents works through a large objective for you: one plans a route you approve, others build it, another checks each leg, and it ends with a pull request."
    )

    var isEnabledByDefault: Bool { false }

    let center = ExpeditionCenter()

    func handle(_ event: SessionEvent) async {
        await center.handle(event)
    }
}
#endif
