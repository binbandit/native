import Foundation

/// Something a script can call. It takes the script's argument object and returns the value the
/// script's `await` produces. Throwing rejects the script's promise with the error's description,
/// which the script can catch.
///
/// A tool is the script's only way to affect anything, so bind only what the caller of the script
/// may already do: a script bypasses whatever approval its caller's individual tool calls get.
public protocol ScriptTool: Sendable {
    func call(_ input: ScriptJSON) async throws -> ScriptJSON
    /// The same, knowing where in the script the call was made, for tools that show it (such as
    /// when they ask the user first). Defaults to `call(_:)`.
    func call(_ input: ScriptJSON, at site: ScriptCallSite?) async throws -> ScriptJSON
}

extension ScriptTool {
    public func call(_ input: ScriptJSON, at site: ScriptCallSite?) async throws -> ScriptJSON {
        try await call(input)
    }
}

/// Where in a script a tool call was made; one-based, as errors report it.
public struct ScriptCallSite: Hashable, Sendable {
    public var line: Int
    public var column: Int?

    public init(line: Int, column: Int? = nil) {
        self.line = line
        self.column = column
    }
}

/// Exposes `tool` to a script as `tools.<path>(input)`, such as `tools.tasks.get({ task_id })`.
public struct ScriptBinding: Sendable {
    public var path: [String]
    /// What the tool does, for the reference `ScriptReference` renders for models.
    public var summary: String?
    /// JSON Schemas of the input object and the result, for that reference.
    public var inputSchema: ScriptJSON?
    public var outputSchema: ScriptJSON?
    public var tool: any ScriptTool

    public init(
        path: [String],
        summary: String? = nil,
        inputSchema: ScriptJSON? = nil,
        outputSchema: ScriptJSON? = nil,
        tool: some ScriptTool
    ) {
        self.path = path
        self.summary = summary
        self.inputSchema = inputSchema
        self.outputSchema = outputSchema
        self.tool = tool
    }

    public init(
        path: [String],
        summary: String? = nil,
        inputSchema: ScriptJSON? = nil,
        outputSchema: ScriptJSON? = nil,
        handler: @escaping @Sendable (ScriptJSON) async throws -> ScriptJSON
    ) {
        self.init(
            path: path, summary: summary, inputSchema: inputSchema, outputSchema: outputSchema,
            tool: ClosureScriptTool(handler: handler))
    }

    /// A tool that also gets the call's place in the script.
    public init(
        path: [String],
        summary: String? = nil,
        inputSchema: ScriptJSON? = nil,
        outputSchema: ScriptJSON? = nil,
        siteHandler: @escaping @Sendable (ScriptJSON, ScriptCallSite?) async throws -> ScriptJSON
    ) {
        self.init(
            path: path, summary: summary, inputSchema: inputSchema, outputSchema: outputSchema,
            tool: SiteClosureScriptTool(handler: siteHandler))
    }

    /// How scripts write the call: `tools.tasks.get`.
    public var label: String { "tools." + path.joined(separator: ".") }

    /// The name the runtime reports calls by; unique because paths are.
    var toolName: String { path.joined(separator: ".") }
}

/// A tool failure with a message for the script.
public struct ScriptToolError: LocalizedError, Sendable {
    public var message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}

private struct ClosureScriptTool: ScriptTool {
    let handler: @Sendable (ScriptJSON) async throws -> ScriptJSON

    func call(_ input: ScriptJSON) async throws -> ScriptJSON {
        try await handler(input)
    }
}

private struct SiteClosureScriptTool: ScriptTool {
    let handler: @Sendable (ScriptJSON, ScriptCallSite?) async throws -> ScriptJSON

    func call(_ input: ScriptJSON) async throws -> ScriptJSON {
        try await handler(input, nil)
    }

    func call(_ input: ScriptJSON, at site: ScriptCallSite?) async throws -> ScriptJSON {
        try await handler(input, site)
    }
}
