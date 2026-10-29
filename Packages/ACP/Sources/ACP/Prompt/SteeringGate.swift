import Foundation

/// A plugin opts into immediate steering only when its adapter preserves running tools.
public enum SteeringPolicy: String, Codable, Hashable, Sendable {
    case afterTools
    case nonInterrupting
    case unknown

    public init(from decoder: any Decoder) throws {
        self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }
}

/// Tracks live tool lifetimes independently of transcript presentation. Missing status fields keep
/// the previous status, and parallel tools must all finish before an interrupting steer is safe.
public struct SteeringGate: Equatable, Sendable {
    public enum Delivery: Equatable, Sendable {
        case waitForTool(String)
        case steer
        case interruptBetweenSteps
    }

    private struct Tool: Equatable, Sendable {
        var id: String
        var title: String
        var status: ToolCallStatus
    }

    private var tools: [Tool] = []

    public init() {}

    /// Queue actions need an advertised extension or an explicit tool-boundary delivery contract.
    /// The default hold policy alone is not an advertisement that the adapter can accept input.
    public static func supportsQueuedSteering(supportsSteering: Bool, policy: SteeringPolicy?) -> Bool {
        supportsSteering || policy == .afterTools
    }

    public func delivery(supportsSteering: Bool, policy: SteeringPolicy = .afterTools) -> Delivery {
        if supportsSteering, policy == .nonInterrupting { return .steer }
        if let tool = tools.first(where: { !$0.status.isFinished }) { return .waitForTool(tool.title) }
        return supportsSteering ? .steer : .interruptBetweenSteps
    }

    public mutating func apply(_ update: SessionUpdate) {
        let call: ToolCallUpdate
        switch update {
        case .toolCall(let value), .toolCallUpdate(let value): call = value
        default: return
        }
        if let index = tools.firstIndex(where: { $0.id == call.toolCallId }) {
            if let title = call.title, !title.isEmpty { tools[index].title = title }
            if let status = call.status { tools[index].status = tools[index].status.reporting(status) }
        } else {
            let title = call.title.flatMap { $0.isEmpty ? nil : $0 } ?? call.name ?? "the tool"
            tools.append(Tool(id: call.toolCallId, title: title, status: call.status ?? .pending))
        }
    }

    public mutating func reset() {
        tools.removeAll()
    }
}
