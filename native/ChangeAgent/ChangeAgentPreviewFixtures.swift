#if DEBUG
import ACP
import Experiments
import Foundation

/// In-memory models only: no agent, Git, file or network work runs in previews.
enum ChangeAgentPreviewFixtures {
    static func app() -> AppModel {
        let experiments = ExperimentStore(catalog: .native, storage: InMemoryExperimentStorage())
        experiments.setValue(.bool(true), for: Gate.changeAgent.id)
        let app = AppModel(
            plugins: PluginRegistry(builtIns: [BuiltInPlugins.claudeCode, BuiltInPlugins.codex]),
            defaults: PreviewUserDefaults(), catalogURL: nil, experiments: experiments)
        _ = app.runtimes.sync()
        return app
    }

    static func source(in app: AppModel) -> SessionModel? {
        let folder = URL(filePath: "/sample")
        let project = app.projects.add(folder)
        guard let source = SessionModel.preview(in: app, cwd: folder.path, title: "Fix the export") else { return nil }
        source.previewExchange("Fix the export", reply: "Updated the writer. Should exports include column headings?")
        app.catalog.add(SessionInfo(sessionId: source.id, cwd: folder.path), for: source.agent.id, in: project.id)
        return source
    }
}
#endif
