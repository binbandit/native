import ACP
import Foundation
import NativeHostProtocol
import NativePolicy

extension SessionModel {
    /// Presentation is shared by Mac, iPad and paired-host sessions. Transport and the host's
    /// recovery journal retain the provider's real controls, so old clients can still reopen them.
    func permissionOptions(_ reported: [ConfigOption]) -> [ConfigOption] {
        let mapping = services.plugins.permissionMapping(for: agent.id)
        let remembered = services.titles.configChoices(for: titleKey)
        return reported.map { option in
            guard option.category == "mode" else { return option }
            let old = remembered.choices[option.id]?.value ?? hostSummary?.permissionMode
            // Migrate only explicit saved levels, never turn an adapter default into a user choice.
            if let old, TaskPermissionMode(rawValue: old) == nil, old != "plan",
                let mode = TaskPermissionMode.migrating(old)
            {
                let shown = mapping.presenting(option, remembered: mode.rawValue)
                services.titles.updateConfigChoices(for: titleKey) { $0.choose(shown, value: mode.rawValue) }
            }
            return mapping.presenting(
                option,
                remembered: services.titles.configChoices(for: titleKey).choices[option.id]?.value
                    ?? hostSummary?.permissionMode)
        }
    }

    func applyPermissionDefault(project: String?, defaults: UserDefaults) async {
        let wanted = TaskPermissionDefaults.value(project: project, defaults: defaults)
        guard let option = configOptions.first(where: { $0.category == "mode" }) else {
            addNotice(
                "This agent does not expose permission controls. Review its permissions before sending.", isError: false
            )
            return
        }
        let allowed = TaskPermissionMode.allCases.reversed().first {
            $0.rank <= wanted.rank
                && !PolicyPermissionModes.forbids(
                    option, value: $0.rawValue, forbidden: services.plugins.policyCenter.policy.forbiddenPermissionModes
                )
        }
        if let allowed { await setConfigOption(option, to: allowed.rawValue) }
    }

    func setConfigOption(_ option: ConfigOption, to value: String) async {
        if option.category == "mode", let mode = TaskPermissionMode(rawValue: value),
            let raw = state.configOptions.first(where: { $0.id == option.id }),
            case .select(_, let offered) = raw.kind
        {
            guard
                !PolicyPermissionModes.forbids(
                    option, value: value, forbidden: services.plugins.policyCenter.policy.forbiddenPermissionModes),
                let selection = services.plugins.permissionMapping(for: agent.id).selection(
                    mode, offered: offered.map(\.value),
                    forbidden: services.plugins.policyCenter.policy.forbiddenPermissionModes)
            else { return }
            services.titles.updateConfigChoices(for: titleKey) { $0.choose(option, value: value) }
            await setProviderConfigOption(raw, to: selection.value, permissionMode: mode.rawValue)
            mirrorState()
            return
        }
        if option.category == "mode" {
            services.titles.updateConfigChoices(for: titleKey) { $0.choose(option, value: value) }
        }
        await setProviderConfigOption(option, to: value)
    }

    private func setProviderConfigOption(_ option: ConfigOption, to value: String, permissionMode: String? = nil) async
    {
        guard case .select(let current, let choices) = option.kind,
            current != value || (host != nil && permissionMode != nil)
        else { return }
        // Every way of changing a setting comes through here, so a forbidden permission mode stops here.
        guard
            !PolicyPermissionModes.forbids(
                option, value: value, forbidden: services.plugins.policyCenter.policy.forbiddenPermissionModes)
        else { return }
        // Remembered for reopening the session; from here on it follows what the agent reports.
        if option.category != "mode" {
            services.titles.updateConfigChoices(for: titleKey) { $0.choose(option, value: value) }
        }
        // Show the choice right away; the agent's answer is authoritative and replaces it.
        replaceConfigOption(option.id, with: .select(currentValue: value, options: choices))
        do {
            if let host {
                // The agent's answer arrives as an update before the host answers.
                try await host.setConfigOption(option.id, to: value, permissionMode: permissionMode)
            } else if let connection {
                let response = try await connection.send(
                    SetConfigOptionRequest(sessionId: id, configId: option.id, value: value))
                state.configOptions = response.configOptions
            }
        } catch {
            replaceConfigOption(option.id, with: option.kind)
            state.appendNotice("Couldn't change \(option.name): \(error.localizedDescription)", isError: true)
        }
    }

    private func replaceConfigOption(_ id: String, with kind: ConfigOption.Kind) {
        guard let index = state.configOptions.firstIndex(where: { $0.id == id }) else { return }
        state.configOptions[index].kind = kind
    }
}
