import ACP
import Foundation

/// Only an explicitly held task is saved. Attachments keep their captured bytes, as queued prompts do.
struct ComposeHeldDraft: Codable {
    struct File: Codable {
        let url: URL
        let byteCount: Int?
        let image: Data?
        let mimeType: String?
        let text: String?

        init(_ attachment: PromptAttachment) {
            url = attachment.url
            byteCount = attachment.byteCount
            switch attachment.content {
            case .image(let data, let mimeType):
                image = data; self.mimeType = mimeType; text = nil
            case .text(let text):
                image = nil; mimeType = nil; self.text = text
            case .reference:
                image = nil; mimeType = nil; text = nil
            }
        }

        var attachment: PromptAttachment {
            let content: PromptAttachment.Content
            if let image, let mimeType {
                content = .image(image, mimeType: mimeType)
            } else if let text {
                content = .text(text)
            } else {
                content = .reference
            }
            return PromptAttachment(url: url, content: content, byteCount: byteCount)
        }
    }

    let project: Project.ID
    let agent: AgentDefinition.ID
    let device: SessionDevice
    let text: String
    let files: [File]
    let choices: [String: String]
    let workspace: TaskWorkspaceChoice?
    /// The second agent on the To line, and the settings its task starts with.
    var second: AgentDefinition.ID?
    var secondChoices: [String: String]?
}
