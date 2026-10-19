import Foundation

/// Which of the user's local checkouts a pull request belongs in, judged by their git remotes:
/// a checkout of the base repository first, then one of the fork the head lives in (the author's
/// own clone of their fork, say), each spelled however its remote URL spells it.
public enum PullRequestProjectMatch {
    public struct Candidate<ID: Hashable & Sendable>: Sendable, Hashable {
        public var id: ID
        public var remotes: [GitRemote]

        public init(id: ID, remotes: [GitRemote]) {
            self.id = id
            self.remotes = remotes
        }
    }

    /// How a checkout relates to the pull request, weakest first.
    public enum Kind: Int, Sendable, Comparable {
        /// A remote names the head's fork on what looks like an SSH alias of its host.
        case forkAliased
        /// A remote is the fork the head lives in.
        case fork
        /// A remote names the base repository on what looks like an SSH alias of its host.
        case repositoryAliased
        /// A remote is the base repository.
        case repository

        public static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public struct Result<ID: Hashable & Sendable>: Sendable, Hashable {
        public var id: ID
        public var kind: Kind
    }

    /// The best checkout among `candidates`, in their order when two match equally well (the
    /// sidebar's order, so the one the user put first wins). `nil` when none has a remote for
    /// either repository.
    public static func best<ID>(
        base: RemoteRepository, head: RemoteRepository?, among candidates: [Candidate<ID>]
    ) -> Result<ID>? {
        var best: Result<ID>?
        for candidate in candidates {
            guard let kind = kind(of: candidate.remotes, base: base, head: head) else { continue }
            if best.map({ kind > $0.kind }) ?? true {
                best = Result(id: candidate.id, kind: kind)
            }
        }
        return best
    }

    static func kind(of remotes: [GitRemote], base: RemoteRepository, head: RemoteRepository?) -> Kind? {
        remotes.compactMap { remote -> Kind? in
            guard let repository = remote.repository else { return nil }
            switch repository.match(base) {
            case .exact: return .repository
            case .aliasedHost: return .repositoryAliased
            case nil: break
            }
            switch head.flatMap(repository.match) {
            case .exact: return .fork
            case .aliasedHost: return .forkAliased
            case nil: return nil
            }
        }
        .max()
    }
}
