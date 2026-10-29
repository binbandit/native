import ACP
import Foundation
import NativeHostProtocol

// The user's own picks, as opposed to settings Native changes (restoring a session, applying
// defaults, policy): a pick of the model or one of its variants is also what the agent's new
// sessions start on from then on (`AgentSessionDefaults.lastUsed`).
extension SessionModel {
    /// Attribution uses the task's remembered choice, not a coincidentally matching default.
    func hasChosenConfig(_ option: ConfigOption) -> Bool {
        guard case .select(let value, _) = option.kind,
            services.titles.configChoices(for: titleKey).choices[option.id]?.value == value
        else { return false }
        return true
    }

    /// Sets `option` to `value` because the user picked it (the composer's controls).
    func pick(_ option: ConfigOption, value: String) async {
        // The agent's own option: while the session loads, the composer shows the choices it's
        // about to get back (`shownConfigOptions`), which the agent isn't on yet.
        let agentHad = state.configOptions.first { $0.id == option.id }
        let settled = phase != .loading && !mirror.isLoading && !isSettingBackConfig
        await setConfigOption(option.category == "mode" ? option : agentHad ?? option, to: value)
        let agentHas = state.configOptions.first { $0.id == option.id }
        guard
            NewSessionChoices.remembersPick(
                value, from: option, agentHad: agentHad, agentHas: agentHas, settled: settled)
        else { return }
        AgentSessionDefaults.updateLastUsed(for: agent.id) { $0.choose(option, value: value) }
    }
}
