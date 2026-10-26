#if DEBUG
import ACP
import CodeThemes
import SwiftUI

extension View {
    @ViewBuilder func appearanceVisualCheckFixture() -> some View {
        if UserDefaults.standard.bool(forKey: "nativeAppearanceVisualCheck") {
            AppearanceVisualCheckFixture()
        } else {
            self
        }
    }
}

struct AppearanceVisualCheckFixture: View {
    @State private var app = Self.model()
    @State private var registry = PluginRegistry(
        previewing: [AppearanceFixturePlugin()],
        disabled: UserDefaults.standard.bool(forKey: "nativeAppearancePluginOff") ? ["lantern"] : [])
    @State private var settings = Self.presentation()
    @State private var appearance = AppearanceModeController()
    @State private var icons = AppIconPreferences()
    @State private var terminal = TerminalStore()

    var body: some View {
        SettingsScreen(pane: $settings.pane)
            .environment(app)
            .environment(registry)
            .environment(settings)
            .environment(appearance)
            .environment(icons)
            .environment(terminal)
            .environment(PolicyCenter.shared)
            .environment(\.experimentStore, SettingsPreviewFixtures.plainly())
            .appearancePreferences(plugins: registry)
            .performanceDriver(app)
    }

    private static func presentation() -> SettingsPresentation {
        let value = SettingsPresentation()
        value.open(.appearance)
        return value
    }

    private static func model() -> AppModel {
        let app = AppModel.preview(.empty)
        let folder = "/fixture/pier"
        _ = app.projects.add(URL(filePath: folder))
        guard let session = SessionModel.preview(in: app, agent: "codex", cwd: folder, title: "Retry uploads") else {
            return app
        }
        let sample = SpecimenLine.sample()
        let prefix = String(repeating: "\n", count: 20)
        var call = ToolCallUpdate(
            toolCallId: "appearance-fixture", title: "Update chunker.ts", kind: .edit, status: .completed)
        call.content = [
            .diff(
                FileDiff(
                    path: "chunker.ts",
                    oldText: prefix + sample.deleted.map(\.text).joined(separator: "\n"),
                    newText: prefix + sample.added.map(\.text).joined(separator: "\n")))
        ]
        session.state.appendUserMessage("Retry uploads")
        session.state.apply(.toolCall(call))
        session.state.endTurn(.endTurn)
        return app
    }
}
#endif
