import ACP
import Foundation
import NativeHostProtocol

/// Which of a client's MCP servers a session on a paired host gets: only ones the host can reach
/// itself, over HTTP to another machine. Servers on the client's loopback (Native's own tools) and
/// commands naming the client's paths mean nothing there; the host's own servers serve its sessions.
public enum PairedHostServers {
    public static func reachable(_ servers: [JSONValue]) -> [JSONValue] {
        servers.filter { server in
            guard case .object(let fields) = server, fields["command"] == nil,
                case .string(let address)? = fields["url"], let url = URL(string: address),
                let host = url.host(), url.scheme == "https" || url.scheme == "http"
            else { return false }
            return !isLoopback(host)
        }
    }

    private static func isLoopback(_ host: String) -> Bool {
        let host = host.lowercased()
        return host == "localhost" || host == "::1" || host.hasPrefix("127.")
    }
}

extension HostProjectList {
    /// Where a project cloned onto this host goes: the folder most of its projects share, else
    /// `Developer` in the home folder its task worktrees live in. Nil when neither says.
    public var cloneFolder: String? {
        let parents = projects.map { URL(filePath: $0.path).deletingLastPathComponent().path(percentEncoded: false) }
            .map { $0.count > 1 && $0.hasSuffix("/") ? String($0.dropLast()) : $0 }
        let counts = Dictionary(parents.map { ($0, 1) }, uniquingKeysWith: +)
        // The most shared, and the first-added among equals, so the answer doesn't change by chance.
        if let common = parents.max(by: { counts[$0, default: 0] < counts[$1, default: 0] }) { return common }
        let suffix = "/.native/worktrees"
        guard worktreesFolder.hasSuffix(suffix) else { return nil }
        return String(worktreesFolder.dropLast(suffix.count)) + "/Developer"
    }
}
