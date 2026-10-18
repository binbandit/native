import ACP
import SwiftUI
import UniformTypeIdentifiers

// Files and images going out with the draft: picked, pasted or dropped. Each is read off the main
// actor, then added through the session, and the composer says what it couldn't take.
extension ComposerView {
    func attach(_ urls: [URL]) {
        load(urls.map { url in { try PromptAttachment.load(url) } })
    }

    func attachImage(_ data: Data, type: UTType) {
        load([{ try PromptAttachment.pasted(data, type: type) }])
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
        let loaders: [@Sendable () throws -> PromptAttachment] = dropped.compactMap { item in
            switch item {
            case .file(let url) where url.isFileURL:
                return { try PromptAttachment.load(url) }
            case .file(let url):
                links.append(url.absoluteString)
                return nil
            case .image(let data, let type):
                return { try PromptAttachment.pasted(data, type: type) }
            }
        }
        if !links.isEmpty {
            let separator = session.draft.isEmpty || session.draft.last?.isWhitespace == true ? "" : " "
            session.draft += separator + links.joined(separator: " ")
        }
        load(loaders)
    }

    private func load(_ loaders: [@Sendable () throws -> PromptAttachment]) {
        guard !loaders.isEmpty else { return }
        isFocused = true
        Task {
            var added: [PromptAttachment] = []
            var problems: [String] = []
            for loader in loaders {
                do {
                    let attachment = try await Self.run(loader)
                    try session.attach(attachment)
                    added.append(attachment)
                } catch {
                    problems.append(error.localizedDescription)
                }
            }
            if let problem = ComposerAttachmentNote.problems(problems) {
                feedback = ComposerFeedback(tone: .problem, message: problem)
            } else if let note = ComposerAttachmentNote.fallback(
                for: added, capabilities: session.promptCapabilities, agentName: session.agentName)
            {
                feedback = ComposerFeedback(tone: .notice, message: note)
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

    func removeAttachment(_ id: PromptAttachment.ID) {
        session.removeAttachment(id)
    }
}
