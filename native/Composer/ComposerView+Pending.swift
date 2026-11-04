import ACP
import Modes
import SwiftUI

extension ComposerView {
    @ViewBuilder
    var fieldQueue: some View {
        if !session.queuedPrompts.isEmpty {
            ComposerQueueSection(
                messages: session.queuedPrompts.map {
                    .init(
                        id: $0.id,
                        text: PromptQuote.summary($0.text).split(whereSeparator: \.isNewline).joined(separator: " "),
                        attachments: $0.attachments.map(\.name))
                },
                sendNowHelp: session.sendNowRoute.map {
                    $0 == .steer
                        ? "Send now: add it to the running turn after tools finish"
                        : "Send now: send it as the next message"
                },
                onSendNow: { sendNow($0) }, onRemove: remove, onEdit: edit,
                onMove: { session.moveQueued($0, $1) }, onDrop: { session.moveQueued($0, before: $1) })
        }
    }

    var fieldCommands: [ComposerSlashCommand] {
        var commands = nativeCommands
        if page == nil {
            commands.append(.init(native: "plan", description: "Plan the next change"))
        }
        return commands + session.availableCommands.map(ComposerSlashCommand.init)
    }

    func submitField() {
        let message = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        let isAgentCommand = agentCommandDraft.map(draftText.hasPrefix) ?? false
        if page == nil, !isAgentCommand, message == "/plan" {
            draftText = ""
            Task { await taskModes.select(.plan, in: session) }
            return
        }
        submit(.queue)
    }

}
