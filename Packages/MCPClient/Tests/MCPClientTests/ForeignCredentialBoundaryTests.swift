import Foundation
import Testing

@Suite("Foreign credential boundary")
struct ForeignCredentialBoundaryTests {
    @Test func productionSourcesNeverReferenceForeignSecretStores() throws {
        var root = URL(filePath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let manager = FileManager.default
        #expect(manager.fileExists(atPath: root.appending(path: "AGENTS.md").path))
        let forbidden = [
            "Claude Code-credentials", ".credentials.json", "CLAUDE_SECURESTORAGE_CONFIG_DIR",
            "auth.json", "hosts.yml", "state.vscdb", "cursorAuth/accessToken", "cursor-access-token",
            "codex-cli", "Codex Auth", "gh:github.com", "git:https://", "find-generic-password",
            "find-internet-password", "\"auth\", \"token\"", "gh auth token",
        ]
        // New Keychain readers require an ownership audit, even if they build service names dynamically.
        let nativeKeychainReaders: Set<String> = [
            "Packages/MCPClient/Sources/MCPClient/Managed/SecretStore.swift",
            "Packages/NativeHost/Sources/NativeHostMac/HostKeychain.swift",
            "Packages/NativeLink/Sources/NativeLink/Device/PairedHostStore.swift",
        ]
        var scanned = 0
        for directory in ["native", "Packages", "NativeHostHelper", "Companion", "Runtime"] {
            let enumerator = try #require(
                manager.enumerator(
                    at: root.appending(path: directory), includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]))
            for case let file as URL in enumerator {
                if ["Tests", "Fixtures", "node_modules", "target"].contains(file.lastPathComponent) {
                    enumerator.skipDescendants()
                    continue
                }
                guard ["swift", "rs", "js", "ts", "m", "c", "h"].contains(file.pathExtension),
                    try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
                else { continue }
                let path = String(file.path.dropFirst(root.path.count + 1))
                let source = try String(contentsOf: file, encoding: .utf8)
                scanned += 1
                for reference in forbidden {
                    #expect(!source.contains(reference), "\(path) references a foreign credential store: \(reference)")
                }
                if source.contains("SecItemCopyMatching") || source.contains("SecKeychainFind") {
                    #expect(nativeKeychainReaders.contains(path), "Audit Keychain ownership in \(path)")
                }
            }
        }
        #expect(scanned > 100)
    }
}
