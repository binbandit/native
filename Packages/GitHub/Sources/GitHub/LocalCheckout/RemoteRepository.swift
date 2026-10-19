import Foundation

/// The GitHub repository a git remote points at. Git accepts many spellings of the same
/// repository (`https://github.com/Owner/Name.git`, `git@github.com:owner/name`,
/// `ssh://git@ssh.github.com:443/owner/name.git`), and GitHub ignores case in owners and names, so
/// two values compare equal whenever they name the same repository on the same host.
public struct RemoteRepository: Sendable, CustomStringConvertible {
    /// Lowercased, with GitHub's alternate SSH and web hosts folded into `github.com`.
    public let host: String
    /// As written, for showing and for URLs; compared without case.
    public let owner: String
    public let name: String

    public init(host: String = "github.com", owner: String, name: String) {
        self.host = Self.canonicalHost(host)
        self.owner = owner
        self.name = name
    }

    /// From `owner/name`, as gh prints `nameWithOwner`.
    public init?(nameWithOwner: String, host: String = "github.com") {
        let parts = nameWithOwner.split(separator: "/")
        guard parts.count == 2 else { return nil }
        self.init(host: host, owner: String(parts[0]), name: String(parts[1]))
    }

    /// From a remote's URL in any form git takes for a hosted repository: a URL (`https`, `http`,
    /// `ssh`, `git`) or scp-like `[user@]host:owner/name`. `nil` for local paths and for URLs that
    /// aren't `owner/name` on a host.
    public init?(remoteURL: String) {
        let text = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let host: String
        let path: String
        if text.contains("://") {
            guard let url = URL(string: text), let urlHost = url.host(), !urlHost.isEmpty else { return nil }
            host = urlHost
            path = url.path(percentEncoded: false)
        } else if let colon = text.firstIndex(of: ":"), !text[..<colon].contains("/") {
            // scp-like: everything before the colon is `[user@]host`.
            let authority = text[..<colon]
            host = String(authority.split(separator: "@").last ?? authority)
            path = String(text[text.index(after: colon)...])
        } else {
            return nil
        }
        var parts = path.split(separator: "/").map(String.init)
        guard parts.count == 2, !host.isEmpty else { return nil }
        if parts[1].lowercased().hasSuffix(".git") { parts[1].removeLast(4) }
        guard !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        self.init(host: host, owner: parts[0], name: parts[1])
    }

    /// `owner/name`.
    public var nameWithOwner: String {
        "\(owner)/\(name)"
    }

    public var description: String {
        host == "github.com" ? nameWithOwner : "\(host)/\(nameWithOwner)"
    }

    /// How a remote's repository relates to this one, weakest first.
    public enum Match: Int, Sendable, Comparable {
        /// The same owner and name on a host that looks like an SSH alias for this one
        /// (`github-work`, `github.com-personal`), which only the user's SSH config could confirm.
        case aliasedHost
        case exact

        public static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// Whether `other` is this repository, and how sure that is.
    public func match(_ other: RemoteRepository) -> Match? {
        guard Self.same(owner, other.owner), Self.same(name, other.name) else { return nil }
        if host == other.host { return .exact }
        return Self.isAlias(other.host, of: host) || Self.isAlias(host, of: other.host) ? .aliasedHost : nil
    }

    /// The URL to add as a remote for this repository, spelled like `example` (another of the
    /// project's remotes) so it authenticates the same way: SSH when that's SSH, HTTPS otherwise.
    public func remoteURL(like example: String?) -> String {
        let isSSH = example.map { !$0.contains("://") || $0.hasPrefix("ssh://") } ?? false
        return isSSH ? "git@\(host):\(nameWithOwner).git" : "https://\(host)/\(nameWithOwner).git"
    }

    // MARK: - Helpers

    private static func canonicalHost(_ host: String) -> String {
        let host = host.lowercased()
        return ["ssh.github.com", "www.github.com"].contains(host) ? "github.com" : host
    }

    private static func same(_ lhs: String, _ rhs: String) -> Bool {
        lhs.caseInsensitiveCompare(rhs) == .orderedSame
    }

    /// An SSH alias is a bare name (`github-work`) or the real host with a suffix
    /// (`github.com-work`); another real host (`ghe.example.com`) is a different repository.
    private static func isAlias(_ candidate: String, of host: String) -> Bool {
        !candidate.contains(".") || (candidate.hasPrefix(host) && candidate.count > host.count)
    }
}

extension RemoteRepository: Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.match(rhs) == .exact
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(host)
        hasher.combine(owner.lowercased())
        hasher.combine(name.lowercased())
    }
}

/// A remote of a local checkout, as `git remote -v` lists it.
public struct GitRemote: Sendable, Hashable {
    public var name: String
    /// The fetch URL.
    public var url: String

    public init(name: String, url: String) {
        self.name = name
        self.url = url
    }

    public var repository: RemoteRepository? {
        RemoteRepository(remoteURL: url)
    }
}
