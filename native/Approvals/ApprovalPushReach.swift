import ACP
import ApprovalAnalysis
import SwiftUI

/// What a push would reach, as the task's own clone knows it since its last fetch: the host the
/// remote is on, and for a force-push the commits there that the push would drop. Read by the Git
/// feature through `approvalPushReach`, so the approval never runs git itself.
struct ApprovalPushReach: Equatable {
    struct Commit: Equatable, Identifiable {
        let hash: String
        let subject: String
        let date: Date
        var id: String { hash }
    }

    struct Request: Equatable {
        let session: SessionKey?
        let permission: RequestID?
        let folder: URL
        let target: GitPushTarget
    }

    typealias Loader = @MainActor (Request) async -> Self?

    /// The remote named by the command.
    let remote: String
    let branch: String?
    /// `github.com`, when the remote is a hosted repository rather than a path.
    let host: String?
    /// `binbandit/native`.
    let repository: String?
    /// How many commits the remote branch has that the pushed one doesn't; nil before any fetch.
    let ahead: Int?
    /// The newest of those, for a force-push.
    let dropped: [Commit]

    /// "github.com", or the remote's name for a remote on disk.
    var place: String { host ?? remote }

    /// The target's annotation: "main on github.com · binbandit/native · 3 commits ahead of yours".
    var description: String {
        var parts = ["\(branch ?? "refs selected by Git") on \(place)"]
        if let repository { parts.append(repository) }
        if let ahead, ahead > 0 { parts.append("\(ahead) \(ahead == 1 ? "commit" : "commits") ahead of yours") }
        return parts.joined(separator: " · ")
    }
}

extension EnvironmentValues {
    @Entry var approvalPushReach: ApprovalPushReach.Loader?
}
