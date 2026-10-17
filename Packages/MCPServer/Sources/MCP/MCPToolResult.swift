import Foundation

/// What a tool call returns: text for the model, and optionally the same data structured.
public struct MCPToolResult: Sendable, Hashable {
    public var text: String
    public var structuredContent: JSON?
    /// The call failed in a way the model should see and can act on, such as a bad argument.
    public var isError: Bool

    public init(text: String, structuredContent: JSON? = nil, isError: Bool = false) {
        self.text = text
        self.structuredContent = structuredContent
        self.isError = isError
    }

    public static func error(_ message: String) -> MCPToolResult {
        MCPToolResult(text: message, isError: true)
    }

    var json: [String: JSON] {
        var object: [String: JSON] = ["content": [["type": "text", "text": .string(text)]], "isError": .bool(isError)]
        object["structuredContent"] = structuredContent
        return object
    }
}

/// Thrown by a tool handler to fail the call with a message for the model.
public struct MCPToolError: LocalizedError, Sendable {
    public var message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}
