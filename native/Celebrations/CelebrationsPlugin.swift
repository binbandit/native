import AppAppearance

/// Native's own celebrations (Halloween, Día de Muertos) and their icon sets. Off until the user
/// turns it on (Native starts minimal), and every celebration in it starts off too; turning it on
/// opens Settings ▸ Celebrations to choose.
struct CelebrationsPlugin: NativePlugin {
    static let id = "celebrations"

    let manifest = PluginManifest(
        id: CelebrationsPlugin.id,
        name: "Celebrations",
        description: "Dresses Native's icon and Home for the celebrations you choose, on their dates.",
        iconSets: IconSetContributions(FirstPartyCelebrations.iconSets),
        celebrations: CelebrationContributions(FirstPartyCelebrations.celebrations)
    )

    var isEnabledByDefault: Bool { false }
}
