import ACP
import Foundation

// Setting a reopened session's settings back. Agents replay a loaded session's transcript, but some
// reopen it on their defaults (codex-acp comes back on its default model and mode, claude-agent-acp
// on its default effort), so Native sets back what was chosen for the session (`ConfigChoices`,
// kept by `SessionTitles`). Only options someone changed are touched, once per load, so whatever
// the user or the agent changes afterwards stands. While it loads, the session shows the choices
// already, so the agent's defaults never flash up first.
extension SessionModel {
    /// Sets the chosen settings back where the agent reopened the session on others, then holds it
    /// to the organization's policy, which wins over any choice. What couldn't come back is said
    /// once, in one quiet notice.
    func restoreConfigChoices() async {
        await setBackConfigChoices { $0.phase == .loading }
    }

    /// Takes on the settings chosen in `old`, a session this one replaces because its agent never
    /// saved it (it went away before the first turn), so the task carries on as the user left it.
    func adoptConfigChoices(of old: SessionModel) async {
        let chosen = services.titles.configChoices(for: old.titleKey)
        services.titles.updateConfigChoices(for: titleKey) { $0.adopt(chosen) }
        await setBackConfigChoices { $0.phase != .disconnected }
    }

    /// The options to show for `reported`, the agent's: while the session loads, as restoring will
    /// leave them; otherwise as they are.
    func shownConfigOptions(_ reported: [ConfigOption]) -> [ConfigOption] {
        guard phase == .loading else { return reported }
        return services.titles.configChoices(for: titleKey)
            .preview(reported) { !PolicyPermissionModes.forbids($0, value: $1) }
    }

    /// Sets each chosen setting back, for as long as `isOpen` holds (the agent may go away; then
    /// reopening the session restores again).
    private func setBackConfigChoices(while isOpen: (SessionModel) -> Bool) async {
        var notes: [String] = []
        var forbidden: [(id: String, choice: ConfigChoices.Choice)] = []
        for id in services.titles.configChoices(for: titleKey).restoreOrder(in: state.configOptions) {
            guard isOpen(self) else { return }
            // Read again each time: the user may have changed it meanwhile, and an earlier change
            // (the model) can change what this option offers.
            let choices = services.titles.configChoices(for: titleKey)
            switch choices.restoration(
                of: id, in: state.configOptions, allows: { !PolicyPermissionModes.forbids($0, value: $1) })
            {
            case .set(let option, let value)?:
                await setConfigOption(option, to: value)
            case .unavailable(let choice, let kept)?:
                notes.append(
                    kept.map { "\(agentName) doesn't offer \(choice.valueName) anymore, so this session uses \($0)." }
                        ?? "\(agentName) no longer has a \(choice.optionName) setting, so it couldn't be set back to \(choice.valueName)."
                )
                // The session goes on with the agent's value, and the notice isn't repeated.
                services.titles.updateConfigChoices(for: titleKey) { $0.forget(id) }
            case .forbidden(let choice)?:
                forbidden.append((id, choice))
            case nil:
                continue
            }
        }
        // The agent may also have reopened the session in a mode that's forbidden now.
        await PolicyPermissionModes.enforce(on: self)
        for (id, choice) in forbidden {
            notes.append(
                "Your organization doesn't allow \(choice.valueName), so this session uses \(currentValueName(of: id))."
            )
        }
        if !notes.isEmpty {
            addNotice(notes.joined(separator: " "), isError: false)
        }
    }

    private func currentValueName(of id: String) -> String {
        guard case .select(let current, let values)? = state.configOptions.first(where: { $0.id == id })?.kind else {
            return "the agent's default"
        }
        return values.first { $0.value == current }?.name ?? current
    }
}
