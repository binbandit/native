import ACP
import Foundation

/// A session's transcript, folded from its host event log with ACP's `SessionState` reducer. The
/// host keeps one per session (to know what the agent replayed) and every client keeps one per
/// session it shows, so the same events mean the same transcript everywhere.
public struct SessionMirror: Sendable {
    /// A question the agent is waiting on, oldest first.
    public struct Question: Sendable, Identifiable {
        /// What `_native/session/respond_question` answers it by.
        public let id: String
        public let request: CreateElicitationRequest
    }

    /// The transcript. Clients may add to it (their own notices and approval cards); the next
    /// `reset` drops what they added along with everything else.
    public var state = SessionState()
    /// Between a `reset(loading: true)` and its `loaded`: the agent is replaying history.
    public private(set) var isLoading = false
    /// The last event applied, for attaching again without missing or repeating any.
    public private(set) var lastSeq: Int?
    public private(set) var questions: [Question] = []
    /// The request whose turn ran last: a passing failure of it goes out again under the same id.
    private var turnRequestID: UUID?
    /// The request Native waits to send again after a passing failure.
    private var retryRequestID: UUID?

    public init() {}

    /// Applies one event. Events at or before `lastSeq` were seen already and are skipped, except a
    /// reset, which always starts the transcript over (a new host numbers its events afresh).
    public mutating func apply(_ event: HostEvent) {
        apply(Step(event))
    }

    public mutating func apply(_ events: some Sequence<HostEvent>) {
        for event in events {
            apply(event)
        }
    }

    /// Applies an event decoded beforehand, as `apply(_:)` does.
    public mutating func apply(_ step: Step) {
        let event = step.event
        if case .reset = event.payload {
            // Falls through to the reset below.
        } else if let lastSeq, event.seq <= lastSeq {
            return
        }
        lastSeq = event.seq
        switch (event.payload, step.decoded) {
        case (.reset(let loading), _):
            state = SessionState()
            questions = []
            isLoading = loading
            turnRequestID = nil
            retryRequestID = nil
        case (.loaded, _):
            isLoading = false
            // Nothing the agent replayed runs any more.
            state.endReplay()
        case (.update, .update(let update)):
            // The host's time, so a client attaching later times the turn the same.
            state.apply(update, at: event.at)
        case (.prompt(let prompt), _):
            receive(prompt, at: event.at)
        case (.permissionRequested(let toolCallID, _), .permission(let request)):
            // The id only has to be unique within the transcript; answers go to the host by tool call.
            state.requestPermission(request, id: .string(toolCallID), at: event.at)
        case (.permissionResolved(let toolCallID, _), _):
            state.resolvePermission(toolCallID: toolCallID)
        case (.questionAsked(let questionID, _), .question(let request)):
            questions.append(Question(id: questionID, request: request))
        case (.questionResolved(let questionID), _):
            questions.removeAll { $0.id == questionID }
        case (.turnEnded(let stopReason), _):
            retryRequestID = nil
            state.endTurn(Self.stopReason(stopReason), at: event.at)
        case (.turnFailed(let message, _, let retry), _):
            // The notice says what went wrong, and what Native does about it when it retries.
            state.failTurn(message, retry: retry, at: event.at)
            retryRequestID = retry == nil ? nil : turnRequestID
        case (.notice(let text, let isError), _):
            // The host's only notice while a retry waits is that the user stopped it.
            retryRequestID = nil
            state.stopRetrying(at: event.at)
            state.appendNotice(text, isError: isError)
        case (.recovered(let note), _):
            // A message that never reached the agent cut nothing off.
            if note.action != .resent {
                state.interruptTurn(at: note.interruptedAt)
            }
            state.appendNotice(note.sentence(), isError: note.action == .failed)
            if note.action == .paused {
                // Native gave up on the turn.
                state.endTurn(.error, at: event.at)
            }
        default:
            // Unsupported events, and payloads that didn't decode.
            break
        }
    }

    /// A message Native delivered. One that failed for a passing reason goes out again under the same
    /// request, and its turn carries on; any other ends the wait for that retry, since it went first.
    private mutating func receive(_ prompt: PromptEcho, at date: Date) {
        if prompt.steered {
            if prompt.shown {
                state.appendUserMessage(
                    prompt.text, attachments: prompt.attachments.map(\.messageAttachment),
                    preamble: prompt.preamble?.marker, steered: true, at: date)
            }
            return
        }
        if let id = prompt.requestID, id == retryRequestID {
            retryRequestID = nil
            state.retryTurn()
            return
        }
        retryRequestID = nil
        turnRequestID = prompt.requestID
        if prompt.shown {
            state.appendUserMessage(
                prompt.text, attachments: prompt.attachments.map(\.messageAttachment),
                preamble: prompt.preamble?.marker, at: date)
        } else {
            state.noteUnshownPrompt(at: date)
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
}

extension SessionMirror {
    /// One event with its agent payload decoded, ready to apply. Decoding is most of what applying an
    /// event costs, so a client can make steps off the main actor and apply them there.
    public struct Step: Sendable {
        public let event: HostEvent
        let decoded: Decoded

        enum Decoded: Sendable {
            case none
            case update(SessionUpdate)
            case permission(RequestPermissionRequest)
            case question(CreateElicitationRequest)
        }

        public init(_ event: HostEvent) {
            self.event = event
            decoded =
                switch event.payload {
                case .update(let json): Self.decode(SessionUpdate.self, from: json).map(Decoded.update) ?? .none
                case .permissionRequested(_, let json):
                    Self.decode(RequestPermissionRequest.self, from: json).map(Decoded.permission) ?? .none
                case .questionAsked(_, let json):
                    Self.decode(CreateElicitationRequest.self, from: json).map(Decoded.question) ?? .none
                default: .none
                }
        }

        /// The agent's update, decoded, for an `update` event.
        public var update: SessionUpdate? {
            if case .update(let update) = decoded { update } else { nil }
        }

        /// The agent's request, decoded, for a `permissionRequested` event.
        public var permissionRequest: RequestPermissionRequest? {
            if case .permission(let request) = decoded { request } else { nil }
        }

        /// The agent's question, decoded, for a `questionAsked` event.
        public var question: CreateElicitationRequest? {
            if case .question(let request) = decoded { request } else { nil }
        }

        private static func decode<Value: Decodable>(_ type: Value.Type, from json: JSONValue) -> Value? {
            guard let data = try? JSONEncoder().encode(json) else { return nil }
            return try? JSONDecoder().decode(type, from: data)
        }
    }
}

extension SessionMirror.Step: Decodable {
    private enum PayloadKeys: String, CodingKey {
        case update, request
    }

    /// Decodes an event and its agent payload from one parse, rather than re-encoding the payload
    /// to decode it again: what a client does with every streamed update.
    public init(from decoder: any Decoder) throws {
        let event = try HostEvent(from: decoder)
        let container = try decoder.container(keyedBy: PayloadKeys.self)
        self.event = event
        decoded =
            switch event.payload {
            case .update: (try? container.decode(SessionUpdate.self, forKey: .update)).map(Decoded.update) ?? .none
            case .permissionRequested:
                (try? container.decode(RequestPermissionRequest.self, forKey: .request)).map(Decoded.permission)
                    ?? .none
            case .questionAsked:
                (try? container.decode(CreateElicitationRequest.self, forKey: .request)).map(Decoded.question) ?? .none
            default: .none
            }
    }
}
