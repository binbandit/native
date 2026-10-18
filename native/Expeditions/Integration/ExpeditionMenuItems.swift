import NativeCommands

extension CommandID {
    static let expeditionNew: Self = "expedition.new"
    static let goExpeditions: Self = "go.expeditions"
}

extension NativeCommand {
    /// File ▸ New Expedition… (⌥⌘E) and Go ▸ Expeditions (⇧⌘X).
    static func expeditions(model: AppModel) -> [NativeCommand] {
        [
            // Choosing it is the user asking for expeditions, so it turns the plugin on the first time.
            NativeCommand(
                .expeditionNew, title: "New Expedition…", category: .tasks, systemImage: "map",
                keywords: ["crew", "lead"]
            ) { _ in
                model.plugins.setEnabled(true, for: BuiltInPlugins.expeditions.manifest.id)
                BuiltInPlugins.expeditions.center.isNewExpeditionRequested = true
            }
            .available { _ in !model.projects.all.isEmpty && model.agents.contains { $0.isAvailable } },

            NativeCommand(.goExpeditions, title: "Expeditions", category: .navigation, systemImage: "map") { _ in
                BuiltInPlugins.expeditions.center.show()
            },
        ]
    }
}
