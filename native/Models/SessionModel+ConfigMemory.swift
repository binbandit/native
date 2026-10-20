import ACP
import Foundation
import NativeHostProtocol

// The user's own picks, as opposed to settings Native changes (restoring a session, applying
// defaults, policy): a pick of the model or one of its variants is also what the agent's new
// sessions start on from then on (`AgentSessionDefaults.lastUsed`).
extension SessionModel {
    /// Sets `option` to `value` because the user picked it (the composer's controls).
    func pick(_ option: ConfigOption, value: String) async {
        // The agent's own option: while the session loads, the composer shows the choices it's
        // about to get back (`shownConfigOptions`), which the agent isn't on yet.
        let agentHad = state.configOptions.first { $0.id == option.id }
        let settled = phase != .loading && !mirror.isLoading && !isSettingBackConfig
        await setConfigOption(agentHad ?? option, to: value)
        let agentHas = state.configOptions.first { $0.id == option.id }
        guard
            NewSessionChoices.remembersPick(
                value, from: option, agentHad: agentHad, agentHas: agentHas, settled: settled)
        else { return }
        AgentSessionDefaults.updateLastUsed(for: agent.id) { $0.choose(option, value: value) }
    }
}
