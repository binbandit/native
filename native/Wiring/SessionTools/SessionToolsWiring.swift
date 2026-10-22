/// Registers the built-in tools available in the Session Tools experiment.
@MainActor
enum SessionToolsWiring {
    static func registerBuiltIns(_ registry: SessionToolRegistry, git: GitStore, gitHub: GitHubModel) {
        registry.register(SessionChangesTool.contribution(git: git, gitHub: gitHub))
    }
}
