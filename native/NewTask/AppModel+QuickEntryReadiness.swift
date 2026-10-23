import Foundation

extension AppModel {
    var quickEntryDeviceUnavailable: Bool {
        guard let project = quickEntry.project else { return false }
        return deviceOptions(for: project).first { $0.device == quickEntry.device }?.canStart != true
    }

    var quickEntryReadiness: String {
        guard quickEntry.project.flatMap(projects.project) != nil else {
            return "Choose a project to give the task a place to work."
        }
        if quickEntryDeviceUnavailable {
            return
                "\(deviceName(quickEntry.device)) is unavailable. Your draft stays here while you choose another device."
        }
        guard let runtime = quickEntryRuntime else { return "Choose an agent to start this task." }
        if runtime.needsSignIn { return "\(runtime.agent.displayName) needs you to sign in." }
        return "\(runtime.agent.displayName) · \(runtime.status == .idle ? "Ready" : runtime.status.label)"
    }

    var quickEntryModelName: String? {
        guard let agent = quickEntry.agent else { return nil }
        let value =
            quickEntry.project.flatMap { ProjectTaskDefaults.model(for: $0, agent: agent) }
            ?? AgentSessionDefaults.explicitValue(for: agent, setting: .model)
        if let value {
            return AgentSessionDefaults.offeredChoices(for: agent, setting: .model).first { $0.value == value }?.name
                ?? value
        }
        return switch AgentSessionDefaults.fallback(for: agent, setting: .model) {
        case .lastUsed(let name), .agentDefault(let name): name
        case nil: nil
        }
    }
}
