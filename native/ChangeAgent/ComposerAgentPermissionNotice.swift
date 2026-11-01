import ACP

/// The receipt explains adapter differences separately from managed restrictions.
enum ComposerAgentPermissionNotice {
    static func text(
        _ selection: AgentModelPermissions.Selection, source: SelectSetting?, target: SelectSetting,
        forbidden: Set<String>, agentName: String, offered: [String]
    ) -> String? {
        let level = target.choices.first { $0.value == selection.value }
        let name = level?.askingTitle.lowercased() ?? selection.value
        let unrestricted = AgentModelPermissions.selection(for: source?.value, offered: offered)
        let limitedByPolicy = unrestricted.map { forbidden.contains($0.value) } ?? false
        switch selection.reason {
        case .equivalent:
            return nil
        case .stricter:
            let earlier =
                source?.value == "read-only"
                ? "read-only permissions"
                : source?.current?.askingTitle.lowercased() ?? source?.value ?? "the previous level"
            if selection.value == "read-only" { return "\(agentName) will use read-only permissions for this task." }
            let consequence =
                selection.value == "plan"
                ? "plan before making changes"
                : selection.value == "dontAsk" ? "refuse anything not already allowed" : "ask \(name)"
            if limitedByPolicy {
                let blocked =
                    unrestricted.flatMap { selection in
                        target.choices.first { $0.value == selection.value }?.askingTitle.lowercased()
                    } ?? earlier
                return "\(agentName) can't use '\(blocked)' for this task, so it will \(consequence)."
            }
            return "\(agentName) doesn't offer '\(earlier)', so it will \(consequence)."
        case .safestAvailable:
            if limitedByPolicy {
                return
                    "The closer permission levels aren't allowed for this task. \(agentName) will use '\(name)'. Review permissions before sending."
            }
            return
                "\(agentName) has no level that asks as often. Its safest level is '\(name)'. Review permissions before sending."
        case .unknown:
            return
                "These permission levels can't be compared. \(agentName) will use '\(name)'. Review permissions before sending."
        }
    }

}
