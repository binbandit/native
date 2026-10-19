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
        // Read again each time: the user may change a setting while the session loads.
        await setBackConfigChoices(from: { $0.services.titles.configChoices(for: $0.titleKey) }) {
            $0.phase == .loading
        }
    }

    /// Takes on the settings chosen in `old`, a session this one replaces because its agent never
    /// saved it (it went away before the first turn), so the task carries on as the user left it.
    func adoptConfigChoices(of old: SessionModel) async {
        let chosen = services.titles.configChoices(for: old.titleKey)
        services.titles.updateConfigChoices(for: titleKey) { $0.adopt(chosen) }
        // From what `old` chose: this session's own record follows each of the agent's answers
        // meanwhile (setting the model resets the effort), since it isn't loading.
        await setBackConfigChoices(from: { _ in chosen }) { $0.phase != .disconnected }
    }

    /// The options to show for `reported`, the agent's: while the session loads, as restoring will
    /// leave them; otherwise as they are.
    func shownConfigOptions(_ reported: [ConfigOption]) -> [ConfigOption] {
        guard phase == .loading else { return reported }
        return services.titles.configChoices(for: titleKey)
            .preview(reported) { !PolicyPermissionModes.forbids($0, value: $1) }
    }

    /// Sets each of the `chosen` settings back, for as long as `isOpen` holds (the agent may go
    /// away; then reopening the session restores again).
    private func setBackConfigChoices(
        from chosen: (SessionModel) -> ConfigChoices, while isOpen: (SessionModel) -> Bool
    ) async {
        var notes: [String] = []
        var forbidden: [(id: String, choice: ConfigChoices.Choice)] = []
        for id in chosen(self).restoreOrder(in: state.configOptions) {
            guard isOpen(self) else { return }
            // Against the options as they are now: an earlier change (the model) can change what
            // this one offers.
            switch chosen(self).restoration(
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
