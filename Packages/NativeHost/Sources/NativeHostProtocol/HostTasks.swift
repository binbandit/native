import ACP
import Foundation

// Native's tools for agents (the orchestration MCP server) and the tasks sessions hand each other
// with them, run by the host so delegated work keeps going with no client attached. Clients mirror
// the tasks (`_native/tasks/list`, then `_native/tasks/changed`); the transcripts show them as cards
// in their parents' event logs. See docs/durability.md, "Native's tools in the host".
extension HostProtocol.Method {
    /// → `[HostTask]`, oldest first.
    public static let listTasks = "_native/tasks/list"
    /// `ConfigureTasksParams`: whether the host serves Native's tools, and the skills switched off.
    /// Local clients only.
    public static let configureTasks = "_native/tasks/configure"
    /// Host → client: `TaskChangedNotification`, when a task starts or its record changes.
    public static let tasksChanged = "_native/tasks/changed"
    /// Host → client: `AppToolCall`, for the Mac app that offered the tool in `configure`.
    public static let appToolCall = "_native/tasks/app_tool_call"
    /// `AppToolResult`: the Mac app's answer to an `AppToolCall`.
    public static let appToolResult = "_native/tasks/app_tool_result"
    /// `CallToolParams` → `ToolResult`: one of the host's own tools, called for a session (the app's
    /// `run_script` binds them). Local clients only.
    public static let callTool = "_native/tasks/call_tool"
}

/// A task one session handed another agent through Native's tools, as the host remembers it.
/// Sessions are named by their agent and the agent's id for them, which outlast the host's own ids.
public struct HostTask: Codable, Hashable, Sendable, Identifiable {
    /// What agents call it, such as `task-ab12cd`.
    public var id: String
    public var agentID: String
    public var agentSessionID: SessionID
    public var agentName: String
    /// What its card in the parent's transcript says.
    public var title: String
    /// The folder it works in: its parent's. Nil for tasks recorded before it was kept.
    public var cwd: String?
    public var parentAgentID: String
    public var parentAgentSessionID: SessionID
    public var parentAgentName: String
    /// The host's session running it, while the host has one open.
    public var sessionID: HostSessionID?
    /// The host's session of its parent, while the host has one open.
    public var parentSessionID: HostSessionID?
    public var createdAt: Date?

    public init(
        id: String, agentID: String, agentSessionID: SessionID, agentName: String, title: String, cwd: String?,
        parentAgentID: String, parentAgentSessionID: SessionID, parentAgentName: String,
        sessionID: HostSessionID? = nil, parentSessionID: HostSessionID? = nil, createdAt: Date? = nil
    ) {
        self.id = id
        self.agentID = agentID
        self.agentSessionID = agentSessionID
        self.agentName = agentName
        self.title = title
        self.cwd = cwd
        self.parentAgentID = parentAgentID
        self.parentAgentSessionID = parentAgentSessionID
        self.parentAgentName = parentAgentName
        self.sessionID = sessionID
        self.parentSessionID = parentSessionID
        self.createdAt = createdAt
    }
}

public struct TaskChangedNotification: Codable, Sendable {
    public var task: HostTask

    public init(task: HostTask) {
        self.task = task
    }
}

/// What the Mac app decides about Native's tools for the host's sessions.
public struct ConfigureTasksParams: Codable, Hashable, Sendable {
    /// The host gives every session Native's tools at its own address (the default, and the only
    /// choice for a host no app runs next to). Off, the app serves them as it did before the host
    /// ran them, and the host leaves the `native` entry clients hand it alone.
    public var servesTools: Bool
    /// Native's own skills switched off (Settings ▸ Skills), which `list_skills` and `get_skill`
    /// leave out.
    public var disabledSkills: [DisabledNativeSkill]
    /// Tools only the Mac app can answer (`setup_status`, `run_script`), which the host lists for
    /// its sessions and passes to this client. The host keeps them, so they're still listed, and
    /// refused with why, while the app is closed.
    public var appTools: [AppToolDefinition]

    public init(servesTools: Bool, disabledSkills: [DisabledNativeSkill] = [], appTools: [AppToolDefinition] = []) {
        self.servesTools = servesTools
        self.disabledSkills = disabledSkills
        self.appTools = appTools
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        servesTools = try container.decode(Bool.self, forKey: .servesTools)
        disabledSkills = try container.decodeIfPresent([DisabledNativeSkill].self, forKey: .disabledSkills) ?? []
        appTools = try container.decodeIfPresent([AppToolDefinition].self, forKey: .appTools) ?? []
    }
}

/// A tool as MCP lists it (`tools/list`): what the model reads to decide when and how to call it.
public struct AppToolDefinition: Codable, Hashable, Sendable {
    public var name: String
    public var title: String?
    public var description: String
    public var inputSchema: JSONValue
    public var outputSchema: JSONValue?
    /// MCP's tool annotations (`readOnlyHint` and the rest), verbatim.
    public var annotations: JSONValue?

    public init(
        name: String, title: String?, description: String, inputSchema: JSONValue, outputSchema: JSONValue?,
        annotations: JSONValue?
    ) {
        self.name = name
        self.title = title
        self.description = description
        self.inputSchema = inputSchema
        self.outputSchema = outputSchema
        self.annotations = annotations
    }
}

/// A session called a tool the Mac app answers, or (`listing`) the host wants the tool as that
/// session sees it, for `tools/list`.
public struct AppToolCall: Codable, Hashable, Sendable {
    public enum Kind: String, WireEnum {
        case call
        case listing
        case unknown
    }

    public var callID: UUID
    public var kind: Kind
    public var tool: String
    /// The calling session, as the tools know it: Native's id for it, its agent and its folder.
    public var sessionID: HostSessionID
    public var agentID: String
    public var cwd: String
    public var arguments: JSONValue

    public init(
        callID: UUID = UUID(), kind: Kind, tool: String, sessionID: HostSessionID, agentID: String, cwd: String,
        arguments: JSONValue = .object([:])
    ) {
        self.callID = callID
        self.kind = kind
        self.tool = tool
        self.sessionID = sessionID
        self.agentID = agentID
        self.cwd = cwd
        self.arguments = arguments
    }
}

/// What a tool call returned (MCP's `CallToolResult`, its text content in one string).
public struct ToolResult: Codable, Hashable, Sendable {
    public var text: String
    public var structuredContent: JSONValue?
    public var isError: Bool

    public init(text: String, structuredContent: JSONValue? = nil, isError: Bool = false) {
        self.text = text
        self.structuredContent = structuredContent
        self.isError = isError
    }
}

/// The Mac app's answer to an `AppToolCall`: the result of a call, or the tool as listed.
public struct AppToolResult: Codable, Hashable, Sendable {
    public var callID: UUID
    public var result: ToolResult?
    public var listing: AppToolDefinition?

    public init(callID: UUID, result: ToolResult? = nil, listing: AppToolDefinition? = nil) {
        self.callID = callID
        self.result = result
        self.listing = listing
    }
}

public struct CallToolParams: Codable, Hashable, Sendable {
    public var sessionID: HostSessionID
    public var tool: String
    public var arguments: JSONValue

    public init(sessionID: HostSessionID, tool: String, arguments: JSONValue) {
        self.sessionID = sessionID
        self.tool = tool
        self.arguments = arguments
    }
}

/// Native's skills switched off for sessions in a folder (and the folders inside it), or everywhere.
public struct DisabledNativeSkill: Codable, Hashable, Sendable {
    /// Nil for every folder without a choice of its own.
    public var folder: String?
    public var skills: [String]

    public init(folder: String?, skills: [String]) {
        self.folder = folder
        self.skills = skills
    }

    /// The skills off for a session in `cwd`: the closest folder's choice, else the global one.
    public static func off(in cwd: String, _ entries: [DisabledNativeSkill]) -> Set<String> {
        let path = cwd.hasSuffix("/") ? cwd : cwd + "/"
        let closest = entries.filter { entry in
            guard let folder = entry.folder else { return false }
            return path.hasPrefix(folder.hasSuffix("/") ? folder : folder + "/")
        }.max { ($0.folder?.count ?? 0) < ($1.folder?.count ?? 0) }
        return Set((closest ?? entries.first { $0.folder == nil })?.skills ?? [])
    }
}
