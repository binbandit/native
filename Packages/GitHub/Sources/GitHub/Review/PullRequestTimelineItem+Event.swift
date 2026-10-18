import Foundation

extension PullRequestTimelineItem {
    /// Something that happened to the pull request, by someone, at some time.
    public struct Event: Sendable, Hashable, Identifiable {
        public enum Kind: Sendable, Hashable {
            case forcePushed(before: String?, after: String?)
            case labeled(PullRequestLabel)
            case unlabeled(PullRequestLabel)
            /// A user, team or app; `nil` when GitHub no longer says (a deleted account).
            case reviewRequested(String?)
            case merged(commit: String?, into: String?)
            case closed
            case reopened
            case readyForReview
            case convertedToDraft
            case renamed(from: String, to: String)
        }

        public var id: String
        public var actor: String?
        public var date: Date
        public var kind: Kind

        public init(id: String, actor: String?, date: Date, kind: Kind) {
            self.id = id
            self.actor = actor
            self.date = date
            self.kind = kind
        }

        private enum CodingKeys: String, CodingKey {
            case id, actor, createdAt, beforeCommit, afterCommit, label, requestedReviewer, commit,
                mergeRefName,
                previousTitle, currentTitle
        }

        private struct Oid: Decodable {
            var abbreviatedOid: String
        }

        private struct Reviewer: Decodable {
            var login: String?
            var name: String?
        }

        /// `nil` for a type that isn't an event this version shows.
        init?(type: String, decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let kind: Kind
            switch type {
            case "HeadRefForcePushedEvent":
                kind = .forcePushed(
                    before: try container.decodeIfPresent(Oid.self, forKey: .beforeCommit)?.abbreviatedOid,
                    after: try container.decodeIfPresent(Oid.self, forKey: .afterCommit)?.abbreviatedOid)
            case "LabeledEvent":
                kind = .labeled(try container.decode(PullRequestLabel.self, forKey: .label))
            case "UnlabeledEvent":
                kind = .unlabeled(try container.decode(PullRequestLabel.self, forKey: .label))
            case "ReviewRequestedEvent":
                let reviewer = try container.decodeIfPresent(Reviewer.self, forKey: .requestedReviewer)
                kind = .reviewRequested(reviewer?.login ?? reviewer?.name)
            case "MergedEvent":
                kind = .merged(
                    commit: try container.decodeIfPresent(Oid.self, forKey: .commit)?.abbreviatedOid,
                    into: try container.decodeText(forKey: .mergeRefName))
            case "ClosedEvent": kind = .closed
            case "ReopenedEvent": kind = .reopened
            case "ReadyForReviewEvent": kind = .readyForReview
            case "ConvertToDraftEvent": kind = .convertedToDraft
            case "RenamedTitleEvent":
                kind = .renamed(
                    from: try container.decodeIfPresent(String.self, forKey: .previousTitle) ?? "",
                    to: try container.decodeIfPresent(String.self, forKey: .currentTitle) ?? "")
            default:
                return nil
            }
            self.init(
                id: try container.decode(String.self, forKey: .id),
                actor: try container.decodeIfPresent(TimelineLogin.self, forKey: .actor)?.login,
                date: try container.decode(Date.self, forKey: .createdAt),
                kind: kind)
        }
    }
}
