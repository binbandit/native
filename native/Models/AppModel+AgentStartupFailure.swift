import NativeSetup

extension AppModel {
    /// A failed launch needs recovery, not a promise that agents are still getting ready.
    var agentStartupFailure: AgentStartupFailure? {
        AgentStartupFailure(
            agents: agents.map { runtime in
                let state: SetupReport.Agent.State =
                    switch availability(of: runtime.agent) {
                    case .ready, .needsSignIn, .signingIn: .ready
                    case .starting: .starting
                    case .failed: .stopped
                    case .notInstalled: .notInstalled
                    case .disabled: .turnedOff
                    }
                return (runtime.agent.displayName, state)
            })
    }
}
