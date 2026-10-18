import ACP
import SwiftUI
import UniformTypeIdentifiers

// Files and images going out with the draft: picked, pasted or dropped. Each shows as a chip right
// away, is read off the main actor, then added through the session, and the composer says what it
// couldn't take or what the agent will get as a path instead.
extension ComposerView {
    /// A file or image on its way in: what its chip says while it's read, and how to read it.
    typealias AttachmentLoader = (name: String, load: @Sendable () throws -> PromptAttachment)

    func attach(_ urls: [URL]) {
        load(urls.map { url in (url.lastPathComponent, { try PromptAttachment.load(url) }) })
    }

    func attachImage(_ data: Data, type: UTType) {
        load([("Pasted Image", { try PromptAttachment.pasted(data, type: type) })])
    }

    func attach(_ pasted: IncomingAttachments) {
        switch pasted {
        case .files(let urls): attach(urls)
        case .image(let data, let type): attachImage(data, type: type)
        }
    }

    /// Dropped files and images. Links dropped from a browser go into the text instead.
    func attach(_ dropped: [ComposerDropItem]) {
        var links: [String] = []
        let loaders: [AttachmentLoader] = dropped.compactMap { item in
            switch item {
            case .file(let url) where url.isFileURL:
                return (url.lastPathComponent, { try PromptAttachment.load(url) })
            case .file(let url):
                links.append(url.absoluteString)
                return nil
            case .image(let data, let type):
                return ("Dropped Image", { try PromptAttachment.pasted(data, type: type) })
            }
        }
        if !links.isEmpty {
            let separator = session.draft.isEmpty || session.draft.last?.isWhitespace == true ? "" : " "
            session.draft += separator + links.joined(separator: " ")
        }
        load(loaders)
    }

    /// Reads each file in turn, its chip standing in until it lands. Files past the message's limit
    /// aren't read at all.
    private func load(_ loaders: [AttachmentLoader]) {
        guard !loaders.isEmpty else { return }
        isFocused = true
        let room = max(PromptAttachment.Limits.count - session.attachments.count - pendingAttachments.count, 0)
        let accepted = loaders.prefix(room)
        let pending = accepted.map { ComposerPendingAttachment(name: $0.name) }
        pendingAttachments += pending
        Task {
            var added: [PromptAttachment] = []
            var problems: [any Error] = []
            for (loader, placeholder) in zip(accepted, pending) {
                do {
                    let attachment = try await Self.run(loader.load)
                    try session.attach(attachment)
                    added.append(attachment)
                } catch {
                    problems.append(error)
                }
                pendingAttachments.removeAll { $0.id == placeholder.id }
            }
            if let note = ComposerAttachmentNote.feedback(
                added: added, refused: loaders.count - accepted.count, problems: problems,
                capabilities: session.promptCapabilities, agentName: session.agentName)
            {
                feedback = note
            }
        }
    }

    /// Reading and scaling a large image takes a moment; never on the main actor.
    @concurrent
    private nonisolated static func run(_ loader: @Sendable () throws -> PromptAttachment) async throws
        -> PromptAttachment
    {
        try loader()
    }

    /// Takes a chip off the message, saying so with an Undo (⌘Z works too).
    func removeAttachment(_ id: PromptAttachment.ID) {
        guard let attachment = session.attachments.first(where: { $0.id == id }) else { return }
        session.removeAttachment(id, undoManager: undoManager)
        missingAttachments.remove(id)
        feedback = ComposerFeedback(tone: .done, message: "Removed \(attachment.name)", canUndo: true)
    }

    /// Backspace in an empty draft takes off the last chip, as it would the last token in a field.
    func removeLastAttachment() {
        if let last = session.attachments.last {
            removeAttachment(last.id)
        }
    }

    /// Why the draft's files can't go yet, or nil when they can: some are still being read, or
    /// have gone from disk since they were attached (their chips say so).
    var attachmentsBlockedReason: String? {
        if let reading = pendingAttachments.first {
            let more = pendingAttachments.count - 1
            return more == 0 ? "Still attaching \(reading.name)" : "Still attaching \(reading.name) and \(more) more"
        }
        return nil
    }

    /// Marks attached files that vanished before sending, and says what to do; true when there
    /// were any, so the message waits.
    func flagMissingAttachments() -> Bool {
        let missing = session.missingAttachments
        missingAttachments = Set(missing.map(\.id))
        guard let first = missing.first else { return false }
        let what = missing.count == 1 ? "\(first.name) isn’t" : "\(first.name) and \(missing.count - 1) more aren’t"
        feedback = .blocked(
            "\(what) where \(missing.count == 1 ? "it was" : "they were") anymore, so \(session.agentName) "
                + "would get a path to nothing. Remove \(missing.count == 1 ? "it" : "them") or attach again.")
        return true
    }
}
