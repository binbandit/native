import NativeHostProtocol

extension AgentSpec {
    /// A plugin's agent, as the host launches it.
    init(_ agent: AgentDefinition) {
        self.init(
            id: agent.id.rawValue, name: agent.displayName, command: agent.manifest.command, args: agent.manifest.args,
            env: agent.manifest.env, resolveExecutables: agent.manifest.resolveExecutables,
            requires: agent.manifest.requires, install: agent.manifest.setup?.install,
            authMethods: agent.manifest.authMethods, idleUnloadTimeout: AppModel.idleUnloadTimeout(for: agent)
        )
    }
}
