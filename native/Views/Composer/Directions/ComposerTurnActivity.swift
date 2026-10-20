#if DEBUG
import ACP
import SwiftUI

/// What the running turn is doing right now, in a line ("Running python3 -m unittest"), and since
/// when it runs; for the directions that say so in the composer.
struct ComposerTurnActivity {
    let startedAt: Date?
    let line: String
    let glyph: String

    init(session: SessionModel) {
        let state = session.state
        startedAt = state.turns.last(where: \.isOpen)?.startedAt
        switch state.items.last {
        case .toolCall(let call)?:
            let presentation = ToolPresentation(call)
            let verb = presentation.verb ?? (call.status.isFinished ? "Ran" : "Running")
            line = presentation.subject.isEmpty ? verb : "\(verb) \(presentation.subject)"
            glyph = presentation.glyph.systemImage
        case .message(let message)? where message.role == .thought:
            line = "Thinking"
            glyph = "brain"
        case .message(let message)? where message.role == .agent:
            line = "Writing a reply"
            glyph = "text.alignleft"
        default:
            line = "Working"
            glyph = "circle.dotted"
        }
    }
}

/// An approval in words: what the agent wants to do ("Run touch notes.txt") and the subject alone.
struct ComposerApprovalSummary {
    let verb: String
    let subject: String
    let command: String?

    init(_ call: ToolCallState) {
        let presentation = ToolPresentation(call)
        verb = presentation.verb ?? "Use"
        subject = presentation.subject.isEmpty ? call.title : presentation.subject
        if case .command(let command) = presentation.body {
            self.command = command
        } else {
            command = nil
        }
    }
}
#endif
