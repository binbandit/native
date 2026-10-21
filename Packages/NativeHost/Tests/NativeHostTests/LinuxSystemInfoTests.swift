import Foundation
import NativeHostClient
import NativeHostProtocol
import Testing

@testable import NativeHost

@Suite
struct LinuxSystemInfoTests {
    @Test(arguments: [
        (
            "NAME=Ubuntu\nVERSION=\"24.04.1 LTS (Noble Numbat)\"\nPRETTY_NAME=\"Ubuntu 24.04.1 LTS\"",
            "Ubuntu 24.04.1 LTS"
        ),
        (
            "PRETTY_NAME=\"Debian GNU/Linux 12 (bookworm)\"\nNAME=\"Debian GNU/Linux\"\nID=debian",
            "Debian GNU/Linux 12 (bookworm)"
        ),
        (
            "NAME=\"Alpine Linux\"\nID=alpine\nVERSION_ID=3.20.3\nPRETTY_NAME=\"Alpine Linux v3.20\"",
            "Alpine Linux v3.20"
        ),
        ("PRETTY_NAME=\"\"\nNAME=Debian\nVERSION='12 (bookworm)'", "Debian 12 (bookworm)"),
        ("NAME=Alpine\nVERSION=", "Alpine"),
        (" \t# PRETTY_NAME=Wrong\n\n NAME = 'Example Linux' \t\n VERSION = 1 \r\n", "Example Linux 1"),
        (#"PRETTY_NAME="Example \"quoted\" \\ \$HOME \`uname\` \q""#, #"Example "quoted" \ $HOME `uname` \q"#),
        (#"PRETTY_NAME='Literal $HOME `uname` \path "quoted"'"#, #"Literal $HOME `uname` \path "quoted""#),
        (#"PRETTY_NAME=Example\ Linux\ \$HOME\ \`uname\`"#, "Example Linux $HOME `uname`"),
        (#"PRETTY_NAME="$HOME $(uname) `uname` #literal""#, "$HOME $(uname) `uname` #literal"),
        ("PRETTY_NAME=Old\nPRETTY_NAME=New", "New"),
        ("PRETTY_NAME=Old\nPRETTY_NAME=\"  \"\nNAME=Fallback", "Fallback"),
    ])
    func fixtures(contents: String, expected: String) {
        #expect(HostLinuxReleaseInfo.displayName(contents) == expected)
    }

    @Test(arguments: [
        "", "# comment\nID=ubuntu\nVERSION_ID=24.04", "NAME=\"  \"",
        "PRETTY_NAME=", "PRETTY_NAME", "PRETTY_NAME=\"unfinished", "PRETTY_NAME='unfinished",
        #"PRETTY_NAME="one""two""#, #"PRETTY_NAME="one" trailing"#, "PRETTY_NAME=two words",
        "PRETTY_NAME=unfinished\\", "PRETTY_NAME=bad\"quote",
    ])
    func malformedOrEmpty(contents: String) {
        #expect(HostLinuxReleaseInfo.displayName(contents) == nil)
        #expect(HostLinuxReleaseInfo.displayName(contents + "\nNAME=Fallback") == "Fallback")
    }

    @Test
    func versionNeedsName() {
        #expect(HostLinuxReleaseInfo.displayName("VERSION=12") == nil)
        #expect(HostLinuxReleaseInfo.displayName("NAME=Debian\nVERSION=12") == "Debian 12")
    }

    @Test(
        arguments: [nil, "", "PRETTY_NAME=", "PRETTY_NAME=\"unfinished", "NAME=Local", "PRETTY_NAME=Local"] as [String?]
    )
    func filePrecedence(local: String?) {
        var reads: [String] = []
        let name = HostLinuxReleaseInfo.systemName(fallback: "Foundation") { path in
            reads.append(path)
            if path == "/etc/os-release" {
                guard let local else { throw CocoaError(.fileReadNoSuchFile) }
                return local
            }
            return "PRETTY_NAME=Vendor\nVERSION=99"
        }
        #expect(name == (local == nil ? "Vendor" : local?.contains("Local") == true ? "Local" : "Foundation"))
        #expect(reads == (local == nil ? ["/etc/os-release", "/usr/lib/os-release"] : ["/etc/os-release"]))
    }

    @Test(arguments: [CocoaError.Code.fileReadNoSuchFile, .fileReadNoPermission])
    func unavailableFiles(code: CocoaError.Code) {
        var reads: [String] = []
        let name = HostLinuxReleaseInfo.systemName(fallback: "Foundation") { path in
            reads.append(path)
            throw CocoaError(code)
        }
        #expect(name == "Foundation")
        #expect(reads == ["/etc/os-release", "/usr/lib/os-release"])
        #expect(
            HostLinuxReleaseInfo.systemName { path in
                if path == "/etc/os-release" { throw CocoaError(.fileReadNoPermission) }
                return "NAME=Vendor\nVERSION=1"
            } == "Vendor 1")
    }

    @Test
    func portableSystemInfo() {
        let info = HostSystemInfo.portable
        var expected = ProcessInfo.processInfo.operatingSystemVersionString
        #if os(Linux)
        let contents =
            (try? String(contentsOfFile: "/etc/os-release", encoding: .utf8))
            ?? (try? String(contentsOfFile: "/usr/lib/os-release", encoding: .utf8))
        expected = contents.flatMap(HostLinuxReleaseInfo.displayName) ?? expected
        #endif
        #expect(info.system == expected)
        #expect(info.model == nil)
        #expect(info.loadAverage().map { $0 >= 0 } ?? true)
    }

    @Test
    @HostActor
    func statusAPIUsesPortableInfo() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "linux-system-info-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let core = try HostCore(
            configuration: .init(
                location: HostLocation(directory: root), hostInfo: PeerInfo(name: "test", version: "1", build: "1"),
                machineName: "test", bootTime: nil, environment: { [:] }, exit: { _ in }))
        let client = NativeHostClient(
            transport: InProcessTransport { stream in await core.accept(stream, grants: .owner) },
            clientInfo: PeerInfo(name: "tests", version: "1", build: "1"))
        await client.start()
        do {
            _ = try await client.connected()
            let status = try await client.hostStatus()
            #expect(status.system == HostSystemInfo.portable.system)
            #expect(status.model == nil)
        } catch {
            await client.stop()
            throw error
        }
        await client.stop()
    }
}
