import ACP
import ApprovalAnalysis
import Foundation
import Git
import GitHub

/// Answers the approval's question of what a push would reach, from the task's own clone on the
/// task's own machine. It reads remotes and remote-tracking refs only: never a fetch, so the answer
/// is as of the last time that clone talked to its remote, and nothing leaves the machine to get it.
@MainActor
enum AppApprovalPushReach {
    static let droppedLimit = 3

    static func make(git: GitStore) -> ApprovalPushReach.Loader {
        { request in
            let model = git.model(for: request.folder, session: request.session)
            if model.repository == nil { await model.refreshNow() }
            guard let repository = model.repository else { return nil }
            let target = request.target
            // Implicit pushes depend on push.default and configured refspecs. Only name a
            // destination supplied by the command, rather than guessing from the upstream.
            guard let remote = target.remote else { return nil }
            var branch = target.branch
            if branch == nil, let source = target.source {
                branch = try? await repository.pushBranch(for: source, to: remote)
            }
            let fetchURL = (try? await repository.remoteURLs())?.first { $0.name == remote }?.url
            let pushURLs = try? await repository.pushURLs(for: remote)
            // A remote can push to several repositories; never describe only one as the target.
            if let pushURLs, pushURLs.count != 1 { return nil }
            let url = pushURLs?.first ?? remote
            let hosted = RemoteRepository(remoteURL: url)
            var drops: (total: Int, newest: [CommitSummary])?
            if target.forces, !target.deletes, fetchURL == url, let branch {
                drops = try? await repository.commits(
                    on: branch, of: remote, missingFrom: target.source ?? "HEAD", limit: droppedLimit)
            }
            return ApprovalPushReach(
                remote: remote, branch: branch, host: hosted?.host, repository: hosted?.nameWithOwner,
                ahead: drops?.total,
                dropped: drops?.newest.map { .init(hash: $0.hash, subject: $0.subject, date: $0.date) } ?? [])
        }
    }
}
