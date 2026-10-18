import ACP
import Foundation
import MCPClient
import ScriptRuntime

/// One `run_script` run's calls to scripted servers, as the session it runs for sees them: each
/// is a quiet line in its transcript, and one that can make changes asks first, the way the
/// agent's own calls do. The session's own mode decides: one that runs tool calls unasked doesn't
/// ask here either. One card at a time; "Allow for This Script" covers the run's remaining calls.
@MainActor final class MCPScriptRun {
    enum Verdict {
        case allowed
        case declined(String)
    }

    private let clientID: UUID
    /// When the card gives up, a little before the script runs out of time, so the call fails with
    /// a reason the agent can act on.
    private let expiry: ContinuousClock.Instant
    private weak var library: MCPLibrary?
    private var allowsEverything = false
    private var isAsking = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    /// The agent's run_script call, found on the first call.
    private lazy var parent: String? = link?.runningScriptCall

    init(clientID: UUID, deadline: ContinuousClock.Instant, library: MCPLibrary) {
        self.clientID = clientID
        expiry = max(deadline - .seconds(2), .now + .seconds(1))
        self.library = library
    }

    private var link: MCPScriptSessionLink? {
        library?.host?.mcpScriptSession(clientID)
    }

    /// Shows a call the script is making, before it runs or asks.
    func begin(_ tool: MCPToolInfo, of server: MCPScriptedServer, input: ScriptJSON, site: ScriptCallSite?) -> String {
        let id = "native-script-call-" + UUID().uuidString
        guard let link else { return id }
        var call = ToolCallUpdate(
            toolCallId: id, title: "\(server.name) · \(tool.name)", kind: tool.isReadOnly == true ? .read : .other,
            status: .pending)
        call.name = tool.name
        call.rawInput = try? JSONValue(convertingFrom: input)
        var script: [String: JSONValue] = ["server": .string(server.name), "tool": .string(tool.name)]
        script["parent"] = parent.map(JSONValue.string)
        script["line"] = site.map { .number(Double($0.line)) }
        call.meta = .object(["native": .object(["script": .object(script)])])
        link.record(call)
        return id
    }

    func update(_ id: String, to status: ToolCallStatus) {
        link?.record(ToolCallUpdate(toolCallId: id, status: status))
    }

    /// Whether the call may run: read-only tools always may; others when the session runs tool
    /// calls unasked, the user allowed it before, or the user says so now.
    func approve(
        _ id: String, tool: MCPToolInfo, of server: MCPScriptedServer, input: ScriptJSON, site: ScriptCallSite?
    ) async -> Verdict {
        guard tool.isReadOnly != true else { return .allowed }
        let label = "tools.\(server.name).\(tool.name)"
        while isAsking { await withCheckedContinuation { waiting.append($0) } }
        if allowsEverything || library?.isAlwaysAllowedInScripts(tool.name, of: server.key) == true {
            return .allowed
        }
        guard let link else { return .declined("\(label) needs approval, but its session is gone.") }
        if link.approvesToolCallsUnasked { return .allowed }

        isAsking = true
        defer {
            isAsking = false
            let next = waiting
            waiting = []
            next.forEach { $0.resume() }
        }
        var call = ToolCallUpdate(toolCallId: id, status: .pending)
        // The card's title says where in the script the call is.
        call.title = "\(server.name) · \(tool.name)" + (site.map { " (script line \($0.line))" } ?? "")
        let answer = await link.requestApproval(for: call, options: Self.options(for: tool), until: expiry)
        link.record(ToolCallUpdate(toolCallId: id, title: "\(server.name) · \(tool.name)"))
        guard let answer else {
            return ContinuousClock.now >= expiry
                ? .declined(
                    "\(label) was still waiting for the user's approval when the script's time ran low. Ask them to approve it, then run the script again."
                )
                : .declined("The approval of \(label) was cancelled.")
        }
        switch Choice(rawValue: answer.optionId) {
        case .once: return .allowed
        case .script:
            allowsEverything = true
            return .allowed
        case .always:
            library?.alwaysAllowInScripts(tool.name, of: server.key)
            return .allowed
        case .reject, nil:
            return .declined("The user declined \(label). Ask them before trying it again.")
        }
    }

    private enum Choice: String {
        case once, script, always, reject
    }

    private static func options(for tool: MCPToolInfo) -> [PermissionOption] {
        [
            PermissionOption(optionId: Choice.once.rawValue, name: "Allow Once", kind: .allowOnce),
            PermissionOption(optionId: Choice.script.rawValue, name: "Allow for This Script", kind: .allowAlways),
            PermissionOption(optionId: Choice.always.rawValue, name: "Always Allow \(tool.name)", kind: .allowAlways),
            PermissionOption(optionId: Choice.reject.rawValue, name: "Reject", kind: .rejectOnce),
        ]
    }
}

extension JSONValue {
    /// The same JSON, from the script runtime's type.
    init(convertingFrom value: ScriptJSON) throws {
        self = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
    }
}
