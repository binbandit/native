import ACP
import Foundation

/// A session's transcript, folded from its host event log with ACP's `SessionState` reducer. The
/// host keeps one per session (to know what the agent replayed) and every client keeps one per
/// session it shows, so the same events mean the same transcript everywhere.
public struct SessionMirror: Sendable {
    public private(set) var state = SessionState()
    /// Between a `reset(loading: true)` and its `loaded`: the agent is replaying history.
    public private(set) var isLoading = false
    /// The last event applied, for attaching again without missing or repeating any.
    public private(set) var lastSeq: Int?

    public init() {}

    /// Applies one event. Events at or before `lastSeq` were seen already and are skipped, except a
    /// reset, which always starts the transcript over (a new host numbers its events afresh).
    public mutating func apply(_ event: HostEvent) {
        if case .reset = event.payload {
            // Falls through to the reset below.
        } else if let lastSeq, event.seq <= lastSeq {
            return
        }
        lastSeq = event.seq
        switch event.payload {
        case .reset(let loading):
            state = SessionState()
            isLoading = loading
        case .loaded:
            isLoading = false
        case .update(let update):
            if let update = Self.decode(SessionUpdate.self, from: update) {
                state.apply(update)
            }
        case .prompt(let prompt):
            state.appendUserMessage(prompt.text, steered: prompt.steered)
        case .permissionRequested(let toolCallID, let request):
            if let request = Self.decode(RequestPermissionRequest.self, from: request) {
                // The id only has to be unique within the transcript; answers go to the host by tool call.
                state.requestPermission(request, id: .string(toolCallID))
            }
        case .permissionResolved(let toolCallID, _):
            state.resolvePermission(toolCallID: toolCallID)
        case .turnEnded(let stopReason):
            state.endTurn(Self.stopReason(stopReason))
        case .turnFailed(let message):
            state.appendNotice(message, isError: true)
        case .notice(let text, let isError):
            state.appendNotice(text, isError: isError)
        case .recovered(let note):
            state.appendNotice(note.sentence(), isError: note.action == .failed)
        case .unsupported:
            break
        }
    }

    public mutating func apply(_ events: some Sequence<HostEvent>) {
        for event in events {
            apply(event)
        }
    }

    /// The user's messages in order, as the agent recorded them (after a replay) or Native sent them.
    public var userMessages: [String] {
        state.items.compactMap { item in
            if case .message(let message) = item, message.role == .user { message.text } else { nil }
        }
    }

    /// An ACP stop reason from its wire name; unknown names stay as `.other`.
    public static func stopReason(_ raw: String) -> StopReason {
        guard let data = try? JSONEncoder().encode(raw),
            let reason = try? JSONDecoder().decode(StopReason.self, from: data)
        else {
            return .other(raw)
        }
        return reason
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, from json: JSONValue) -> Value? {
        guard let data = try? JSONEncoder().encode(json) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
