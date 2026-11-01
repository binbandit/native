import Foundation

extension TaskHandoff {
    /// Source identities are local transcript references. The full conversation stays in Native;
    /// no foreign tool calls, attachments or private reasoning are replayed.
    public static func context(
        source: ContextTransfer.SessionReference, title: String, state: SessionState,
        objective: String? = nil, changedPaths: [String] = [], fileStatus: String? = nil
    ) -> ContextTransfer.Draft {
        var items: [ContextTransfer.Item] = []
        var omitted: [ContextTransfer.Omission] = []
        func append(_ id: String, kind: ContextTransfer.Kind, text: String, position: Int) {
            items.append(.init(reference: .init(source: source, id: id, kind: kind, position: position), text: text))
        }
        if let objective, !objective.isEmpty { append("goal", kind: .goal, text: objective, position: -1) }
        for (position, item) in state.items.enumerated() {
            switch item {
            case .message(let message) where message.role != .thought:
                append(item.id, kind: message.role == .user ? .user : .agent, text: message.text, position: position)
                for (index, _) in message.attachments.enumerated() {
                    omitted.append(
                        .init(source: source, id: "\(item.id)/attachment/\(index)", reason: .attachmentNotReplayed))
                }
            case .message:
                omitted.append(.init(source: source, id: item.id, reason: .reasoning))
            case .notice:
                omitted.append(.init(source: source, id: item.id, reason: .localNotice))
            case .toolCall, .subagent, .sessionMessage:
                omitted.append(.init(source: source, id: item.id, reason: .toolState))
            }
        }
        if items.isEmpty { append("title", kind: .goal, text: title, position: 0) }
        for (index, entry) in state.plan.enumerated() {
            append(
                "plan/\(index)", kind: .plan, text: "[\(entry.status.rawValue)] \(entry.content)",
                position: state.items.count + index)
        }
        let paths = Set(changedPaths + state.turns.flatMap { state.summary(of: $0).changedFiles.map(\.path) }).sorted()
        for (index, path) in paths.enumerated() {
            append("file/\(path)", kind: .file, text: path, position: state.items.count + state.plan.count + index)
        }
        if let fileStatus {
            append(
                "file-status", kind: .status, text: fileStatus,
                position: state.items.count + state.plan.count + paths.count)
        }
        return .init(items: items, omitted: omitted)
    }
}
