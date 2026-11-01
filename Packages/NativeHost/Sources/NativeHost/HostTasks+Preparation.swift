import ACP
import Foundation
import NativeHostProtocol
import NativeOrchestration

extension HostTasks {
    func checkParent(_ parent: HostSession, request: TaskRequest) throws {
        guard core.sessions[parent.id] === parent, ref(of: parent) == request.parent,
            parent.stopRequestedAt == nil, parent.configChange == nil,
            stopEpochs[parent.id, default: 0] == request.delegationEpoch,
            coordinatorScope(of: parent.id.rawValue) == nil
        else {
            throw TaskLaunchValidation.Refusal(
                "The parent stopped, closed, or can no longer delegate. Start again from a live task.")
        }
        if let reason = request.agent.unavailableReason { throw TaskLaunchValidation.Refusal(reason) }
        try core.require(.agentTools)
        try core.require(agent: request.agent.id)
        try core.requirePermission(in: parent)
        guard core.agents[request.agent.id]?.hostAgent.needsSignIn != true,
            core.agents[request.agent.id]?.hostAgent.authStatus?.kind != .signedOut
        else {
            throw TaskLaunchValidation.Refusal("The requested agent requires sign-in in Native.")
        }
    }

    func checkout(_ requested: String?, parent: HostSession) async throws -> String {
        try TaskLaunchValidation.checkout(requested, inherited: URL(filePath: parent.record.cwd)).path
    }

    func prepare(_ session: HostSession, request: TaskRequest, parent: HostSession) async throws {
        if let model = request.options.model {
            try await select(model, category: "model", in: session)
        }
        // Model changes can change the effort menu, so inspect the acknowledged response again.
        if let effort = request.options.effort {
            try await select(effort, category: "thought_level", in: session)
        }
        try checkParent(parent, request: request)
        let (option, value) = try TaskLaunchValidation.permission(
            parent: parent.mirror.state.configOptions, child: session.mirror.state.configOptions,
            requested: request.options.permissions)
        try await core.setConfigOption(SetConfigOptionParams(sessionID: session.id, configID: option.id, value: value))
        try TaskLaunchValidation.verify(option.id, value: value, in: session.mirror.state.configOptions)
        try verifyPrepared(session, request: request, parent: parent)
    }

    private func select(_ value: String, category: String, in session: HostSession) async throws {
        let option = try TaskLaunchValidation.exact(value, category: category, in: session.mirror.state.configOptions)
        try await core.setConfigOption(SetConfigOptionParams(sessionID: session.id, configID: option.id, value: value))
        try TaskLaunchValidation.verify(option.id, value: value, in: session.mirror.state.configOptions)
    }

    func verifyPrepared(_ session: HostSession, request: TaskRequest, parent: HostSession) throws {
        let options = session.mirror.state.configOptions
        for (category, wanted) in [("model", request.options.model), ("thought_level", request.options.effort)] {
            if let wanted {
                let option = try TaskLaunchValidation.exact(wanted, category: category, in: options)
                try TaskLaunchValidation.verify(option.id, value: wanted, in: options)
            }
        }
        let (mode, value) = try TaskLaunchValidation.permission(
            parent: parent.mirror.state.configOptions, child: options, requested: request.options.permissions)
        try TaskLaunchValidation.verify(mode.id, value: value, in: options)
        try core.requirePermission(in: session)
    }
}
