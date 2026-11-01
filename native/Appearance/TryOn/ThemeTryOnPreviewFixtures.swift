#if DEBUG
import CodeThemes
import NativePolicy
import SwiftUI

/// Try On in previews: in-memory defaults and fixture plugins only. Nothing is written to the
/// user's settings, no task opens and no agent starts.
enum ThemeTryOnPreviewFixtures {
    struct Setup {
        let tryOn: ThemeTryOnModel
        let app: AppModel
        let plugins: PluginRegistry
        let settings: SettingsPresentation
    }

    /// A trial under way in `mode`, with `highlighted` tried on.
    @MainActor
    static func trying(
        mode: CodeAppearance = .dark, highlighted: CodeTheme.ID? = nil, plugin: Bool = false,
        backgrounds: ThemeTryOnBackgrounds = .init(light: .paper, dark: .standard)
    ) -> Setup {
        let setup = make(plugin: plugin)
        setup.tryOn.start()
        setup.tryOn.show(mode)
        if let highlighted { setup.tryOn.highlight(highlighted) }
        setup.tryOn.setBackgrounds(backgrounds)
        return setup
    }

    /// Back in Settings after Keep, with the kept line under the card.
    @MainActor
    static func kept() -> Setup {
        let setup = make(plugin: false)
        setup.settings.open(.appearance)
        setup.tryOn.start()
        setup.tryOn.highlight(CodeTheme.tokyoNight.id)
        setup.tryOn.keep(undoManager: nil)
        return setup
    }

    @MainActor
    private static func make(plugin: Bool) -> Setup {
        let app = AppModel.preview(.empty)
        let plugins = PluginRegistry(previewing: plugin ? [AppearanceFixturePlugin()] : [])
        let settings = SettingsPresentation()
        let tryOn = ThemeTryOnModel(
            app: app, settings: settings, appearance: AppearanceModeController(defaults: PreviewUserDefaults()),
            plugins: plugins, defaults: PreviewUserDefaults(), policy: { NativePolicy() })
        return Setup(tryOn: tryOn, app: app, plugins: plugins, settings: settings)
    }

    /// The panel in the sidebar's column, on the sidebar's material.
    @MainActor
    static func panel(_ setup: Setup, height: CGFloat = 640) -> some View {
        ThemeTryOnPanel(tryOn: setup.tryOn)
            .frame(width: DS.Size.sidebarWidth, height: height)
            .background(.dsSidebarSolid)
            .themeTryOnPreview(setup.tryOn)
            .environment(setup.app)
            .environment(setup.plugins)
    }
}

#Preview("Try On - Dark mode, Tokyo Night") {
    let setup = ThemeTryOnPreviewFixtures.trying(highlighted: CodeTheme.tokyoNight.id)
    ThemeTryOnPreviewFixtures.panel(setup)
        .environment(\.colorScheme, .dark)
}

#Preview("Try On - Light mode on Wool, Rosé Pine") {
    let setup = ThemeTryOnPreviewFixtures.trying(
        mode: .light, highlighted: CodeTheme.rosePine.id, backgrounds: .init(light: .wool, dark: .standard))
    ThemeTryOnPreviewFixtures.panel(setup)
        .environment(\.colorScheme, .light)
}

#Preview("Try On - In use highlighted, True Black") {
    let setup = ThemeTryOnPreviewFixtures.trying(backgrounds: .init(light: .paper, dark: .trueBlack))
    ThemeTryOnPreviewFixtures.panel(setup)
        .environment(\.colorScheme, .dark)
}

#Preview("Try On - With a plugin's themes") {
    let setup = ThemeTryOnPreviewFixtures.trying(highlighted: "lantern/moss", plugin: true)
    DSPreviewPair { ThemeTryOnPreviewFixtures.panel(setup, height: 760) }
}

#Preview("Try On - A task needs you") {
    let app = AppModel.preview(.empty)
    let session = SessionModel.preview(in: app, title: "Retry uploads when the network drops")
    session?.previewPermissionRequest(command: "bun test src/upload")
    return DSPreviewPair {
        ThemeTryOnNeedsYouStrip(tasks: session.map { [$0] } ?? []) { _ in }
            .frame(width: DS.Size.sidebarWidth)
    }
}

#Preview("Try On - Kept, back in Settings") {
    let setup = ThemeTryOnPreviewFixtures.kept()
    DSPreviewPair {
        CodeThemeSettingsRow(defaults: PreviewUserDefaults(), fixedSpecimen: AppearancePreviewFixtures.latest)
            .frame(width: DS.Settings.pageWidth)
            .padding(DS.Space.xl)
    }
    .environment(setup.tryOn)
    .environment(setup.plugins)
    .environment(AppearancePreviewFixtures.policyCenter(locked: false))
    .environment(setup.settings)
    .environment(\.settingsPlainly, true)
}
#endif
