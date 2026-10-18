import Foundation

/// A tool the server offers. Its name, description and schemas are what the model reads to decide
/// when and how to call it, so write them for a model.
public struct MCPTool<Context: Sendable>: Sendable {
    public var name: String
    public var title: String?
    public var description: String
    /// A JSON Schema for the arguments object.
    public var inputSchema: JSON
    /// A JSON Schema the structured results conform to, if they have one.
    public var outputSchema: JSON?
    public var annotations: MCPToolAnnotations
    /// What one client sees of the tool in `tools/list`, when that depends on the client: a
    /// description naming what it can reach, say, with annotations to match. Nil lists the tool
    /// as declared.
    public var listing: (@Sendable (Context) async -> Listing)?

    public struct Listing: Sendable {
        public var description: String
        public var annotations: MCPToolAnnotations

        public init(description: String, annotations: MCPToolAnnotations) {
            self.description = description
            self.annotations = annotations
        }
    }

    private let call: @Sendable (Context, JSON) async -> MCPToolResult

    /// A tool whose arguments decode as `Arguments`. Arguments that don't decode, and errors the
    /// handler throws, become error results so the model can read them and correct itself.
    public init<Arguments: Decodable & Sendable>(
        name: String,
        title: String? = nil,
        description: String,
        inputSchema: JSON,
        outputSchema: JSON? = nil,
        annotations: MCPToolAnnotations = MCPToolAnnotations(),
        arguments: Arguments.Type = Arguments.self,
        handler: @escaping @Sendable (Context, Arguments) async throws -> MCPToolResult
    ) {
        self.name = name
        self.title = title
        self.description = description
        self.inputSchema = inputSchema
        self.outputSchema = outputSchema
        self.annotations = annotations
        call = { context, json in
            let arguments: Arguments
            do {
                arguments = try json.decode(Arguments.self)
            } catch {
                return .error("Invalid arguments for \(name): \(Self.describe(error))")
            }
            do {
                return try await handler(context, arguments)
            } catch {
                return .error((error as? LocalizedError)?.errorDescription ?? "\(error)")
            }
        }
    }

    /// Calls the tool directly, for servers that let one tool call others (such as a script).
    public func callAsFunction(_ context: Context, arguments: JSON) async -> MCPToolResult {
        await call(context, arguments)
    }

    func definition(for context: Context) async -> JSON {
        let listed = await listing?(context) ?? Listing(description: description, annotations: annotations)
        var object: [String: JSON] = [
            "name": .string(name), "description": .string(listed.description), "inputSchema": inputSchema,
        ]
        object["title"] = title.map(JSON.string)
        object["outputSchema"] = outputSchema
        object["annotations"] = listed.annotations.json
        return .object(object)
    }

    private static func describe(_ error: any Error) -> String {
        let path = { (context: DecodingError.Context) in context.codingPath.map(\.stringValue).joined(separator: ".") }
        return switch error {
        case DecodingError.keyNotFound(let key, _): "missing required argument \"\(key.stringValue)\"."
        case DecodingError.typeMismatch(_, let context), DecodingError.valueNotFound(_, let context):
            "argument \"\(path(context))\" has the wrong type."
        case DecodingError.dataCorrupted(let context):
            "argument \"\(path(context))\" is invalid: \(context.debugDescription)"
        default: "\(error)"
        }
    }
}

/// Hints about a tool's behavior. Clients treat them as untrusted; they're for presentation.
public struct MCPToolAnnotations: Sendable, Hashable {
    public var readOnly: Bool?
    public var destructive: Bool?
    public var idempotent: Bool?
    /// Whether the tool reaches beyond a closed set of things, such as the internet.
    public var openWorld: Bool?

    public init(readOnly: Bool? = nil, destructive: Bool? = nil, idempotent: Bool? = nil, openWorld: Bool? = nil) {
        self.readOnly = readOnly
        self.destructive = destructive
        self.idempotent = idempotent
        self.openWorld = openWorld
    }

    var json: JSON? {
        let hints = [
            "readOnlyHint": readOnly, "destructiveHint": destructive, "idempotentHint": idempotent,
            "openWorldHint": openWorld,
        ]
        .compactMapValues { $0.map(JSON.bool) }
        return hints.isEmpty ? nil : .object(hints)
    }
}
