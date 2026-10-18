import Foundation

/// One pull request, wherever it lives: `host/owner/name#number`. The identity the pull request
/// page, its cache and links share, built from a web URL or a list row.
public struct PullRequestReference: Hashable, Sendable, Codable {
    /// `github.com`, or a GitHub Enterprise host.
    public var host: String
    public var owner: String
    public var name: String
    public var number: Int

    public init(host: String = "github.com", owner: String, name: String, number: Int) {
        self.host = host
        self.owner = owner
        self.name = name
        self.number = number
    }

    /// From a pull request's web URL, `https://host/owner/name/pull/123`, ignoring anything after
    /// the number (`/files`, `#discussion_r1`).
    public init?(url: URL) {
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 4, parts[2] == "pull", let number = Int(parts[3]), let host = url.host()
        else {
            return nil
        }
        self.init(host: host, owner: parts[0], name: parts[1], number: number)
    }

    public init?(_ summary: PullRequestSummary) {
        self.init(url: summary.url)
    }

    /// `owner/name`.
    public var repository: String {
        "\(owner)/\(name)"
    }

    /// `owner/name#123`.
    public var display: String {
        "\(repository)#\(number)"
    }

    public var url: URL {
        URL(string: "https://\(host)/\(owner)/\(name)/pull/\(number)") ?? URL(filePath: "/")
    }

    /// `GH_HOST` for commands about it: `nil` for github.com, gh's default.
    var ghHost: String? {
        host == "github.com" ? nil : host
    }
}
