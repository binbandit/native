extension BuiltInPlugins {
    /// Pi, the minimal coding agent, through `pi-acp`, the adapter the ACP registry lists for it. Pi
    /// speaks its own RPC protocol (`pi --mode rpc`), not ACP, so the adapter translates, running
    /// the user's own `pi` so their providers, sign-in, skills and extensions apply. The adapter is
    /// pinned like the others; it is young and moves fast.
    ///
    /// Sign-in is Pi's own (`/login` in `pi`, or provider API keys in the environment). The adapter
    /// turns `session/new` away with `auth_required` when Pi has no usable model.
    static let pi = ManifestPlugin(manifest: PluginManifest(
        id: "pi",
        name: "Pi",
        description: "The minimal coding agent, through the pi-acp adapter.",
        agents: [AgentManifest(
            id: "pi",
            name: "Pi",
            symbol: "pi",
            command: "npx",
            args: ["--yes", "pi-acp@0.0.34"],
            resolveExecutables: ["PI_ACP_PI_COMMAND": "pi"],
            icon: AgentIconSource(registry: "pi-acp"),
            requires: ["pi"],
            setup: AgentSetupGuide(
                install: "npm install -g --ignore-scripts @earendil-works/pi-coding-agent",
                docs: URL(string: "https://pi.dev"),
                signIn: "pi"
            )
        )]
    ))
}
