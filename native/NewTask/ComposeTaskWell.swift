import SwiftUI

/// The toolbar well before Start: the agent and whether the task can start. A view of its own so the
/// toolbar item observes the runtime itself; a value computed by the page reached the screen but left
/// the item's accessibility label stale.
struct ComposeTaskWell: View {
    let model: AppModel
    let compose: ComposeTaskModel
    let entry: QuickEntryModel

    var body: some View { TaskWellLabel(content: readiness) }

    private var readiness: TaskWellContent {
        let agent = model.quickEntryRuntime?.agent.displayName ?? compose.editor?.agentName ?? "Choose agent"
        if compose.stage != .writing { return .init(status: .starting, agent: agent, verb: "Starting") }
        if entry.project == nil { return .init(status: .idle, agent: agent, verb: "· Needs a folder") }
        if model.composeDeviceOption?.canStart == false {
            if model.composeDeviceOption?.availability == .connecting {
                return .init(status: .starting, agent: "", verb: "Connecting to \(model.deviceName(entry.device))")
            }
            if model.composeDeviceOption?.availability == .online {
                return .init(status: .needsInput, agent: "", verb: "Needs a checkout")
            }
            return .init(
                status: .needsInput, agent: "",
                verb: "Waiting for \(model.composeDeviceOption?.name ?? model.deviceName(entry.device))")
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
        return .init(status: .idle, agent: agent, verb: "· Ready")
    }
}
