import ACP
import SwiftUI
import UniformTypeIdentifiers

// Files and images going out with the draft: picked, pasted or dropped. Each shows as a chip right
// away, is read off the main actor, then added through the session, and the composer says what it
// couldn't take or what the agent will get as a path instead.
extension ComposerView {
    /// Reads one file or image into an attachment; it blocks, so it runs off the main actor.
    typealias AttachmentRead = @Sendable () throws -> PromptAttachment
    /// A file or image on its way in: what its chip says while it's read, and how to read it.
    typealias AttachmentLoader = (name: String, load: AttachmentRead)

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
        case .failed(let name): feedback = .blocked("Couldn’t attach \(name). Try attaching it with Attach Files.")
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
            case .failed(let name):
                return (name, { throw PromptAttachment.LoadError.unreadable(name: name) })
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
        let reads = session.attachmentReads
        reads.begin(pending.count, in: session)
        Task {
            var added: [PromptAttachment] = []
            var problems: [any Error] = []
            for (loader, placeholder) in zip(accepted, pending) {
                do {
                    let attachment: PromptAttachment
                    do { attachment = try await Self.run(loader.load) } catch { reads.failed(); throw error }
                    try reads.complete(attachment)
                    added.append(attachment)
                } catch {
                    problems.append(error)
                }
                pendingAttachments.removeAll { $0.id == placeholder.id }
            }
            let destination = reads.destination ?? session
            if let note = ComposerAttachmentNote.feedback(
                added: added, refused: loaders.count - accepted.count, problems: problems,
                capabilities: destination.promptCapabilities, agentName: destination.agentName)
            {
                feedback = note
            }
        }
    }

    /// Reading and scaling a large image takes a moment; never on the main actor.
    @concurrent
    private nonisolated static func run(_ read: AttachmentRead) async throws -> PromptAttachment {
        try read()
    }

    /// Takes a chip off the message, saying so with an Undo (⌘Z works too).
    func removeAttachment(_ id: PromptAttachment.ID) {
        guard let attachment = session.attachments.first(where: { $0.id == id }) else { return }
        session.removeAttachment(id, undoManager: undoManager)
        missingAttachments.remove(id)
        feedback = ComposerFeedback(tone: .done, message: "Removed \(attachment.name)", canUndo: true)
    }

    /// The chip the keyboard has selected, by its place among the attachments.
    var selectedAttachmentIndex: Int? {
        session.attachments.firstIndex { $0.id == selectedAttachment }
    }

    /// Selects the chip at `index`, or with nil, hands the keys back to the text. VoiceOver hears
    /// which chip, since the selection is drawn rather than focused.
    func selectAttachment(at index: Int?) {
        let attachment = index.flatMap { session.attachments.indices.contains($0) ? session.attachments[$0] : nil }
        guard attachment?.id != selectedAttachment else { return }
        selectedAttachment = attachment?.id
        if let attachment {
            AccessibilityNotification.Announcement(
                "\(attachment.name) selected. Delete removes it; Escape returns to the message."
            ).post()
        }
    }

    /// Why the draft can't go yet because of its files, or nil when it can: some are still being
    /// read, and the message waits for them.
    var attachmentsBlockedReason: String? {
        guard let reading = pendingAttachments.first else { return nil }
        let more = pendingAttachments.count - 1
        return more == 0 ? "Still attaching \(reading.name)" : "Still attaching \(reading.name) and \(more) more"
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
