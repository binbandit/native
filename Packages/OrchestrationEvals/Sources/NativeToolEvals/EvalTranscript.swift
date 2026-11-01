import Foundation
import MCP

/// A normalized trace, independent of provider transcripts and the host's history schema.
public struct EvalTranscript: Codable, Sendable {
    public enum Completion: String, Codable, Sendable {
        case complete, stepLimit, infrastructureError
    }

    public struct Call: Codable, Sendable {
        public var tool: String
        public var arguments: JSON
        public var result: JSON?
        public var isError: Bool

        public var succeeded: Bool { !isError && result?["isError"] == .bool(false) }

        public init(tool: String, arguments: JSON = [:], result: JSON? = nil, isError: Bool = false) {
            self.tool = tool
            self.arguments = arguments
            self.result = result
            self.isError = isError
        }
    }

    public var caseID: String
    public var calls: [Call]
    public var finalText: String
    public var completion: Completion

    public init(
        caseID: String, calls: [Call] = [], finalText: String = "", completion: Completion = .complete
    ) {
        self.caseID = caseID
        self.calls = calls
        self.finalText = finalText
        self.completion = completion
    }
}
