import ACP
import Foundation

/// Accepted file reads belong to the task's continuing draft. Retain its model only while reads
/// are outstanding, so a late result cannot land on a closed or earlier conversation.
final class ComposerAttachmentReads {
    private(set) var count = 0
    private weak var owner: SessionModel?
    private var retainedOwner: SessionModel?

    var destination: SessionModel? { retainedOwner ?? owner }

    func begin(_ count: Int, in session: SessionModel) {
        guard count > 0 else { return }
        if owner == nil { owner = session }
        self.count += count
        retainedOwner = owner
    }

    func move(to session: SessionModel) {
        owner = session
        if count > 0 { retainedOwner = session }
        session.attachmentReads = self
    }

    func complete(_ attachment: PromptAttachment) throws {
        defer {
            count = max(0, count - 1)
            if count == 0 { retainedOwner = nil }
        }
        guard let destination else { throw SessionModel.SendError.disconnected }
        try destination.attach(attachment)
    }

    func failed() {
        count = max(0, count - 1)
        if count == 0 { retainedOwner = nil }
    }
}
