import SwiftUI

/// The toolbar well before Start: the agent and whether the task can start. It observes the runtime in
/// its own body, and speaks through a plain text representation: in a toolbar item, the glass label's
/// own accessibility element keeps the first label it had ("Starting") after it redraws as Ready.
struct ComposeTaskWell: View {
    let model: AppModel
    let compose: ComposeTaskModel
    let entry: QuickEntryModel

    var body: some View {
        TaskWellLabel(content: readiness)
            .accessibilityRepresentation { Text(readiness.accessibilityText) }
    }

    private var readiness: TaskWellContent {
        let first = model.quickEntryRuntime?.agent.displayName ?? compose.editor?.agentName ?? "Choose agent"
        let secondName = compose.second.map { model.plugins.agent($0.agent)?.displayName ?? $0.agent.rawValue }
        let agent = secondName.map { "\(first) and \($0)" } ?? first
        if compose.stage != .writing { return .init(status: .starting, agent: agent, verb: "Starting") }
        if compose.isHeld {
            return .init(
                status: .idle, agent: "",
                verb: "Held for \(model.composeDeviceOption?.name ?? model.deviceName(entry.device))",
                object: "starts when it's back", objectIsCode: false)
        }
        if model.composeDeviceOption?.canStart == false {
            if model.composeDeviceOption?.availability == .connecting {
                return .init(status: .starting, agent: "", verb: "Connecting to \(model.deviceName(entry.device))")
            }
            if model.composeDeviceOption?.availability == .online {
                return .init(status: .needsInput, agent: "", verb: "Needs a checkout")
            }
            return .init(
                status: .needsInput, agent: "",
                verb: "Waiting for \(model.composeDeviceOption?.name ?? model.deviceName(entry.device))",
                object: model.composeDeviceOfflineSince.map { "offline since \($0)" }, objectIsCode: false)
        }
        if let runtime = model.quickEntryRuntime, runtime.needsSignIn {
            return .init(status: .needsInput, agent: agent, verb: "Sign in to \(agent)")
        }
        if model.quickEntryRuntime?.status == .starting {
            return .init(status: .starting, agent: agent, verb: "Starting")
        }
        if model.quickEntryRuntime == nil {
            return .init(status: .needsInput, agent: "", verb: "Choose an available agent")
        }
        if model.quickEntryRuntime?.isAvailable == false {
            return .init(status: .needsInput, agent: agent, verb: "Needs attention")
        }
        if let secondName, let runtime = model.composeSecondRuntime {
            if runtime.needsSignIn { return .init(status: .needsInput, agent: "", verb: "Sign in to \(secondName)") }
            if runtime.status == .starting { return .init(status: .starting, agent: secondName, verb: "Starting") }
            if !runtime.isAvailable { return .init(status: .needsInput, agent: secondName, verb: "Needs attention") }
        }
        return .init(status: .idle, agent: agent, verb: "Ready", verbIsState: true)
    }
}

#if DEBUG
#Preview("Compose well - Before Start") {
    DSPreviewPair {
        VStack(spacing: DS.Space.md) {
            ForEach(["ready", "firstLaunch", "offline", "held", "twoAgents"], id: \.self) { state in
                let model = ComposeTaskPreviewFixtures.model(state)
                ComposeTaskWell(model: model, compose: model.composeTask, entry: model.quickEntry)
            }
        }
        .padding(DS.Space.xxl)
    }
}
#endif
