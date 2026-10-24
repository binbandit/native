#if DEBUG
import ACP
import Experiments
import Foundation
import NativeHostProtocol

enum CoordinatorTaskPreviewFixtures {
    static func app(empty: Bool = false) -> AppModel {
        let experiments = ExperimentStore(catalog: .native, storage: InMemoryExperimentStorage())
        experiments.set(true, for: .coordinatorTasks)
        let app = AppModel(
            plugins: PluginRegistry(builtIns: [BuiltInPlugins.codex]),
            defaults: PreviewUserDefaults(), catalogURL: nil, experiments: experiments)
        _ = app.runtimes.sync()
        let project = app.projects.add(URL(filePath: "/sample"))
        guard !empty, let agent = app.agents.first?.agent else { return app }
        for (id, title) in [
            ("coordinator", "Align the tools documentation"), ("one", "Document the tools"),
            ("two", "Update the navigation and examples with a longer task title"),
        ] {
            app.catalog.add(
                SessionInfo(sessionId: SessionID(id), cwd: "/sample", title: title), for: agent.id, in: project.id)
        }
        app.coordinators = [
            HostCoordinator(
                task: HostTaskIdentity(agentID: agent.id.rawValue, agentSessionID: SessionID("coordinator")),
                projectPath: "/sample",
                assignments: ["one", "two"].map {
                    HostTaskIdentity(agentID: agent.id.rawValue, agentSessionID: SessionID($0))
                })
        ]
        return app
    }
}
#endif
