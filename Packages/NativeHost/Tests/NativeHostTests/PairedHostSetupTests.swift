import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import Testing

/// What a client sets up for a session on a paired host: the MCP servers it hands over, and where a
/// project cloned there goes.
@Suite struct PairedHostSetupTests {
    @Test func handsOverOnlyServersTheHostCanReachItself() {
        let servers: [JSONValue] = [
            .object([
                "name": .string("native"), "type": .string("http"), "url": .string("http://127.0.0.1:47200/mcp/x"),
            ]),
            .object(["name": .string("local"), "type": .string("http"), "url": .string("http://localhost:3000/mcp")]),
            .object(["name": .string("files"), "command": .string("/Users/me/bin/files-mcp"), "args": .array([])]),
            .object(["name": .string("linear"), "type": .string("http"), "url": .string("https://mcp.linear.app/mcp")]),
            .object(["name": .string("events"), "type": .string("sse"), "url": .string("http://10.0.0.5:9000/sse")]),
        ]
        let names = PairedHostServers.reachable(servers).compactMap { server -> String? in
            guard case .object(let fields) = server, case .string(let name)? = fields["name"] else { return nil }
            return name
        }
        #expect(names == ["linear", "events"])
    }

    @Test func clonesBesideTheHostsOtherProjects() {
        let added = Date(timeIntervalSince1970: 1_800_000_000)
        let listed = HostProjectList(
            projects: [
                HostProject(path: "/Users/mini/Developer/api", addedAt: added),
                HostProject(path: "/Users/mini/scratch/demo", addedAt: added),
                HostProject(path: "/Users/mini/Developer/web", addedAt: added),
            ],
            worktreesFolder: "/Users/mini/.native/worktrees")
        #expect(listed.cloneFolder == "/Users/mini/Developer")
    }

    @Test func clonesIntoDeveloperOnAHostWithNoProjects() {
        #expect(
            HostProjectList(projects: [], worktreesFolder: "/Users/mini/.native/worktrees").cloneFolder
                == "/Users/mini/Developer")
        #expect(HostProjectList(projects: [], worktreesFolder: "/Volumes/Work/trees").cloneFolder == nil)
    }
}
