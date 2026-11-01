import ACP
import Foundation

// Setting a reopened session's settings back. Agents replay a loaded session's transcript, but some
// reopen it on their defaults (codex-acp comes back on its default model and mode, claude-agent-acp
// on its default effort), so Native sets back what was chosen for the session (`ConfigChoices`,
// kept by `SessionTitles`), filling missing model and effort choices from Settings. Choices are
// applied once per load, so whatever the user or the agent changes afterwards stands. While it
// loads, the session shows the choices already, so the agent's defaults never flash up first.
extension SessionModel {
    /// Sets the chosen settings back where the agent reopened the session on others, then holds it
    /// to the organization's policy, which wins over any choice. What couldn't come back is said
    /// once, in one quiet notice.
    func restoreConfigChoices() async {
        // Read again each time: the user may change a setting while the session loads. A host
        // session's settings come back in the host instead (`setBackConfigAfterLoad`).
        let defaults = AgentSessionDefaults.configuredValues(for: agent.id)
        await setBackConfigChoices(from: {
            $0.services.titles.configChoices(for: $0.titleKey).fillingDefaults(defaults, in: $0.configOptions)
        }) {
            $0.phase == .loading
        }
        guard phase == .loading else { return }
        // A default already matching the agent needs no request, but is still this task's choice.
        services.titles.updateConfigChoices(for: titleKey) {
            $0 = $0.fillingDefaults(defaults, in: configOptions)
        }
    }

    /// Takes on the settings chosen in `old`, a session this one replaces because its agent never
    /// saved it (it went away before the first turn), so the task carries on as the user left it.
    func adoptConfigChoices(of old: SessionModel) async {
        await adoptConfigChoices(services.titles.configChoices(for: old.titleKey))
    }

    func adoptConfigChoices(_ chosen: ConfigChoices) async {
        services.titles.updateConfigChoices(for: titleKey) { $0.adopt(chosen) }
        // From what `old` chose: this session's own record follows each of the agent's answers
        // meanwhile (setting the model resets the effort), since it isn't loading.
        await setBackConfigChoices(from: { _ in chosen }) { $0.phase != .disconnected }
        // Two shared modes may use one provider value, so a remembered choice can change only presentation.
        mirrorState()
    }

    /// The options to show for `reported`, the agent's: while the session loads, as restoring will
    /// leave them; otherwise as they are.
    func shownConfigOptions(_ reported: [ConfigOption]) -> [ConfigOption] {
        let reported = permissionOptions(reported)
        guard phase == .loading else { return reported }
        var choices = services.titles.configChoices(for: titleKey)
        if host == nil {
            choices = choices.fillingDefaults(AgentSessionDefaults.configuredValues(for: agent.id), in: reported)
        }
        return choices.preview(reported) { !PolicyPermissionModes.forbids($0, value: $1) }
    }

    /// Sets each of the `chosen` settings back, for as long as `isOpen` holds (the agent may go
    /// away; then reopening the session restores again).
    private func setBackConfigChoices(
        from chosen: (SessionModel) -> ConfigChoices, while isOpen: (SessionModel) -> Bool
    ) async {
        var notes: [String] = []
        var forbidden: [(id: String, choice: ConfigChoices.Choice)] = []
        var attempted: Set<String> = []
        while let id = chosen(self).restoreOrder(in: permissionOptions(state.configOptions)).first(where: {
            !attempted.contains($0)
        }) {
            attempted.insert(id)
            guard isOpen(self) else { return }
            // Against the options as they are now: an earlier change (the model) can change what
            // this one offers.
            switch chosen(self).restoration(
                of: id, in: permissionOptions(state.configOptions),
                allows: { !PolicyPermissionModes.forbids($0, value: $1) })
            {
            case .set(let option, let value)?:
                await setConfigOption(option, to: value)
            case .unavailable(let choice, let kept)?:
                notes.append(
                    kept.map { "\(agentName) doesn't offer \(choice.valueName) anymore, so this task uses \($0)." }
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
                "\(PolicyCenter.organizationSubject) doesn't allow \(choice.valueName), so this task uses \(currentValueName(of: id))."
            )
        }
        if !notes.isEmpty {
            addNotice(notes.joined(separator: " "), isError: false)
        }
    }

    private func currentValueName(of id: String) -> String {
        guard case .select(let current, let values)? = configOptions.first(where: { $0.id == id })?.kind else {
            return "the agent's default"
        }
        return values.first { $0.value == current }?.name ?? current
    }
}
