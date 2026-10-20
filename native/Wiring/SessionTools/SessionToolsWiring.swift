/// Registers the tools Native's own features add to the session screen, in the order their facts
/// show: what changed, what's running, who's helping, where it's going, where it opens.
@MainActor
enum SessionToolsWiring {
    static func registerBuiltIns(
        _ registry: SessionToolRegistry, model: AppModel, git: GitStore, gitHub: GitHubModel, terminals: TerminalStore,
        runner: ProjectActionRunner
    ) {
        registry.register(SessionChangesTool.contribution(git: git, gitHub: gitHub))
        registry.register(SessionRunTool.contribution(model: model, runner: runner, terminals: terminals))
        registry.register(SessionTerminalTool.contribution(terminals: terminals))
        registry.register(SessionSubagentsTool.contribution)
        registry.register(SessionPullRequestTool.contribution(git: git, gitHub: gitHub))
        registry.register(SessionOpenInTool.contribution(model: model))
    }
}
