import Foundation
import MCPClient

/// What `MCPLibrary` keeps on disk: its servers, every switch and the tools scripts may call without
/// asking. Secrets aren't in it.
struct MCPStoreFile: Codable {
    var servers: [ManagedServer] = []
    var switches = MCPServerSwitches()
    var scriptApprovals: [String: Set<String>] = [:]

    init(
        servers: [ManagedServer] = [], switches: MCPServerSwitches = MCPServerSwitches(),
        scriptApprovals: [String: Set<String>] = [:]
    ) {
        self.servers = servers
        self.switches = switches
        self.scriptApprovals = scriptApprovals
    }

    /// Files from older versions lack the newer keys.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        servers = try container.decodeIfPresent([ManagedServer].self, forKey: .servers) ?? []
        switches = try container.decodeIfPresent(MCPServerSwitches.self, forKey: .switches) ?? MCPServerSwitches()
        scriptApprovals = try container.decodeIfPresent([String: Set<String>].self, forKey: .scriptApprovals) ?? [:]
    }
}
