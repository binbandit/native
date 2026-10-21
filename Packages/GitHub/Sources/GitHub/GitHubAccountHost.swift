import Foundation

/// Resolves only the host, leaving repository selection to gh. Ambiguous cross-host checkouts
/// fail closed rather than sending a selected account's credential to another enterprise host.
enum GitHubAccountHost {
    static func resolve(remotes: String, config: String, fallback: String?) throws(GitHubError) -> String {
        var hostsByRemote: [String: Set<String>] = [:]
        for line in remotes.split(separator: "\n") {
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard parts.count >= 3, let repository = RemoteRepository(remoteURL: String(parts[1])) else { continue }
            hostsByRemote[String(parts[0]), default: []].insert(repository.host)
        }
        var resolutions: [String: String] = [:]
        for entry in config.split(separator: "\0") {
            let pair = entry.split(separator: "\n", maxSplits: 1)
            guard pair.count == 2 else { continue }
            let key = String(pair[0])
            if key.hasSuffix(".gh-resolved") {
                resolutions[String(key.dropFirst(7).dropLast(12))] = String(pair[1])
            }
        }
        for (name, resolution) in resolutions.sorted(by: { $0.key < $1.key }) where !resolution.isEmpty {
            if let hosts = hostsByRemote[name], hosts.count == 1, let host = hosts.first {
                if resolution == "base" || resolution.split(separator: "/").count == 2 { return host }
                return GitHubCommand.host(of: resolution, defaultHost: host)
            }
        }
        let hosts = Set(hostsByRemote.values.flatMap { $0 })
        if hosts.count == 1, let host = hosts.first { return host }
        if hosts.isEmpty { return fallback ?? "github.com" }
        throw .notARepository(
            "This checkout has remotes on several GitHub hosts. Choose its default with gh repo set-default, then try again."
        )
    }
}
