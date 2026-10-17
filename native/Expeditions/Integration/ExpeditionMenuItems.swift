import SwiftUI

/// File ▸ New Expedition… (⌥⌘E). Choosing it is the user asking for expeditions, so it turns the
/// plugin on the first time.
struct NewExpeditionMenuItem: View {
    let model: AppModel

    var body: some View {
        Button("New Expedition…") {
            model.plugins.setEnabled(true, for: BuiltInPlugins.expeditions.manifest.id)
            BuiltInPlugins.expeditions.center.isNewExpeditionRequested = true
        }
        .keyboardShortcut("e", modifiers: [.command, .option])
        .disabled(model.projects.all.isEmpty || model.agents.allSatisfy { !$0.isReady })
    }
}

/// Go ▸ Expeditions (⇧⌘X).
struct ExpeditionsMenuItem: View {
    var body: some View {
        Button("Expeditions") {
            BuiltInPlugins.expeditions.center.show()
        }
        .keyboardShortcut("x", modifiers: [.command, .shift])
    }
}
