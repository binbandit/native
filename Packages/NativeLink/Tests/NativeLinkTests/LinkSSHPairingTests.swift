import Exec
import Foundation
import Testing

@testable import NativeLink

/// Add Host's SSH path, with a stand-in ssh that runs the remote script on this Mac, and stand-in
/// Native installs: what the script finds, and what ssh's own failures mean.
@Suite struct LinkSSHPairingTests {
    @Test func runsPairFromTheInstalledNativeWithTheAskedGrants() async throws {
        let rig = try ScriptRig()
        let link = "nativecompanion://pair#e30"
        try rig.install(
            "New.app",
            helper: """
                #!/bin/sh
                # \(LinkPairCommand.marker)
                printf '%s\\n' "$*" >&2
                echo '{"event":"invite","link":"\(link)"}'
                """)
        let (events, ending) = await rig.run(app: "New.app", grants: LinkGrants(runCommands: true))
        #expect(events.map(\.link) == [link])
        #expect(ending == .ran(exitCode: 0))
        #expect(rig.helperArguments == "pair --json --run-commands")
    }

    @Test func passesOnABrowserApprovalTheServerWaitsFor() async throws {
        let rig = try ScriptRig()
        try rig.install(
            "New.app",
            helper: "#!/bin/sh\n# \(LinkPairCommand.marker)\necho '{\"event\":\"invite\",\"link\":\"x\"}'")
        let check =
            "# Tailscale SSH requires an additional check.\n# To authenticate, visit: https://login.tailscale.com/a/l1b2c3"
        var updates: [String] = []
        for await update in rig.updates(app: "New.app", preface: check) {
            switch update {
            case .needsApproval(let url): updates.append("approve \(url.absoluteString)")
            case .event(let event): updates.append("event \(event.event.rawValue)")
            case .ended(let ending): updates.append("ended \(ending)")
            }
        }
        #expect(updates == ["approve https://login.tailscale.com/a/l1b2c3", "event invite", "ended ran(exitCode: 0)"])
    }

    @Test func readsApprovalPages() {
        let tailscale = "# To authenticate, visit: https://login.tailscale.com/a/l1b2c3"
        #expect(LinkSSHPairing.approvalURL(in: tailscale)?.absoluteString == "https://login.tailscale.com/a/l1b2c3")
        #expect(LinkSSHPairing.approvalURL(in: "Welcome! Docs at https://example.com/docs") == nil)
        let waited = CommandResult(
            exitCode: 255, standardOutput: Data(),
            standardError: Data("\(tailscale)\nConnection to elara closed by remote host.\n".utf8))
        guard case .ssh(.notApproved(let url), _) = LinkSSHPairing.ending(waited) else {
            Issue.record("a sign-in nobody approved reads as that")
            return
        }
        #expect(url.absoluteString == "https://login.tailscale.com/a/l1b2c3")
    }

    @Test func neverRunsAHelperFromBeforePair() async throws {
        let rig = try ScriptRig()
        try rig.install("Old.app", helper: "#!/bin/sh\necho started a host >&2\nexit 9", version: "0.9.4")
        let (events, ending) = await rig.run(app: "Old.app", grants: .standard)
        #expect(events.isEmpty)
        #expect(ending == .tooOld(version: "0.9.4"))
    }

    @Test func saysWhenNativeIsntThere() async throws {
        let rig = try ScriptRig()
        let (_, ending) = await rig.run(app: "Missing.app", grants: .standard)
        #expect(ending == .notInstalled)
    }

    @Test func readsSSHsOwnFailures() {
        let cases: [(String, LinkSSHPairing.SSHProblem)] = [
            ("me@mini: Permission denied (publickey,password).", .signIn),
            ("@@@ WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED! @@@\nHost key verification failed.", .hostKey),
            ("Host key verification failed.", .hostKey),
            ("ssh: Could not resolve hostname mini: nodename nor servname provided, or not known", .unknownHost),
            ("ssh: connect to host mini port 22: Connection refused", .refused),
            ("ssh: connect to host 10.0.0.9 port 22: Operation timed out", .unreachable),
            ("kex_exchange_identification: read: Connection reset by peer", .other),
        ]
        for (stderr, problem) in cases {
            #expect(LinkSSHPairing.problem(in: stderr) == problem, "\(stderr)")
        }
        let failed = CommandResult(
            exitCode: 255, standardOutput: Data(), standardError: Data("Permission denied\n".utf8))
        #expect(LinkSSHPairing.ending(failed) == .ssh(.signIn, detail: "Permission denied"))
    }

    @Test func takesOnlyDestinations() {
        #expect(LinkSSHPairing.isDestination("me@mac-mini.local"))
        #expect(LinkSSHPairing.isDestination("mini"))
        #expect(!LinkSSHPairing.isDestination("-oProxyCommand=evil"))
        #expect(!LinkSSHPairing.isDestination("me@mini rm"))
        #expect(!LinkSSHPairing.isDestination("nativecompanion://pair#abc"))
        #expect(!LinkSSHPairing.isDestination(""))
    }

    @Test func prefersThisMacsOwnEdition() throws {
        let script = LinkSSHPairing.script(grants: .standard, appName: "Native Nightly.app")
        let nightly = try #require(script.range(of: "'/Applications'/'Native Nightly.app'")?.lowerBound)
        let stable = try #require(script.range(of: "'/Applications'/'Native.app'")?.lowerBound)
        #expect(nightly < stable)
        #expect(script.components(separatedBy: "/'Native Nightly.app'").count == 3, "once per folder")
    }
}

/// A stand-in ssh that runs the remote command here, searching only a folder of stand-in installs
/// with an empty home, so no real Native is ever found or run.
private final class ScriptRig: Sendable {
    let root = URL(filePath: "/tmp/nl-ssh-\(UUID().uuidString.prefix(8))")

    init() throws {
        try FileManager.default.createDirectory(at: root.appending(path: "home"), withIntermediateDirectories: true)
        try write(
            "#!/bin/sh\nwhile [ $# -gt 0 ]; do case \"$1\" in -o) shift 2;; --) shift; break;; -*) shift;; *) break;; esac; done\nshift\n[ -z \"$SSH_PREFACE\" ] || printf '%s\\n' \"$SSH_PREFACE\" >&2\nexec /bin/sh -c \"$*\"\n",
            to: root.appending(path: "ssh"), executable: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    var helperArguments: String {
        (try? String(contentsOf: root.appending(path: "arguments"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func install(_ name: String, helper: String, version: String = "1.4.0") throws {
        let app = root.appending(path: name)
        let macOS = app.appending(path: "Contents/Library/LoginItems/Native Host.app/Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        let recording = helper.replacingOccurrences(
            of: #"printf '%s\n' "$*" >&2"#, with: #"printf '%s\n' "$*" > "\#(root.path)/arguments""#)
        try write(recording, to: macOS.appending(path: "Native Host"), executable: true)
        let info = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleShortVersionString": version], format: .xml, options: 0)
        try info.write(to: app.appending(path: "Contents/Info.plist"))
    }

    func run(app: String, grants: LinkGrants) async -> ([LinkPairCommandEvent], LinkSSHPairing.Ending?) {
        var events: [LinkPairCommandEvent] = []
        var ending: LinkSSHPairing.Ending?
        for await update in updates(app: app, grants: grants) {
            switch update {
            case .event(let event): events.append(event)
            case .needsApproval: break
            case .ended(let end): ending = end
            }
        }
        return (events, ending)
    }

    /// `preface` is what the stand-in ssh prints to standard error before running the script.
    func updates(
        app: String, grants: LinkGrants = .standard, preface: String = ""
    ) -> AsyncStream<
        LinkSSHPairing.Update
    > {
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = root.appending(path: "home").path
        environment["NATIVE_APP"] = nil
        environment["SSH_PREFACE"] = preface
        return LinkSSHPairing.pair(
            destination: "droid", grants: grants, appName: app, environment: environment,
            ssh: root.appending(path: "ssh").path, folders: [LinkSSHPairing.quoted(root.path)])
    }

    private func write(_ text: String, to url: URL, executable: Bool) throws {
        try Data(text.utf8).write(to: url)
        if executable { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path) }
    }
}
