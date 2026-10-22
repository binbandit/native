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
        // stdout and stderr are independent pipes; neither promises to arrive before the other.
        // Both messages must arrive exactly once, before the command's ending.
        #expect(updates.dropLast().sorted() == ["approve https://login.tailscale.com/a/l1b2c3", "event invite"])
        #expect(updates.last == "ended ran(exitCode: 0)")
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

    @Test func findsThePairCommandInADebugLibrary() async throws {
        let rig = try ScriptRig()
        try rig.install("Debug.app", helper: "#!/bin/sh\necho '{\"event\":\"invite\",\"link\":\"debug-link\"}'")
        let library = rig.root.appending(
            path: "Debug.app/Contents/Library/LoginItems/Native Host.app/Contents/MacOS/Native Host.debug.dylib")
        try Data(LinkPairCommand.marker.utf8).write(to: library)

        let (events, ending) = await rig.run(app: "Debug.app", grants: .standard)
        #expect(events.map(\.link) == ["debug-link"])
        #expect(ending == .ran(exitCode: 0))
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

    @Test(arguments: [
        "Applications/Native.app", "Applications/Native Nightly.app",
        "home/Applications/Native.app", "home/Applications/Native Nightly.app",
    ])
    func manualCommandFindsEachSupportedInstallation(_ installation: String) async throws {
        let rig = try ScriptRig()
        try rig.install(installation, helper: Self.manualHelper)

        let result = try await rig.runManual()

        #expect(result.succeeded)
        #expect(result.output == "fixture pairing link\n")
        #expect(result.errorOutput.contains(installation))
        #expect(!result.errorOutput.contains("Choose the installation"))
        #expect(rig.helperArguments == "pair --run-commands --install-updates")
    }

    @Test(arguments: ["1\n", "2\n"])
    func manualCommandLetsTheOwnerChooseAnEdition(_ choice: String) async throws {
        let rig = try ScriptRig()
        for name in ["Native.app", "Native Nightly.app"] {
            try rig.install("Applications/\(name)", helper: Self.manualHelper + "\necho '\(name)'")
        }

        let result = try await rig.runManual(choice: choice)

        #expect(result.succeeded)
        #expect(result.errorOutput.contains("Choose the installation to pair [1-2]"))
        let selected = choice == "1\n" ? "Native.app" : "Native Nightly.app"
        #expect(result.output == "fixture pairing link\n\(selected)\n")
    }

    @Test(arguments: ["", "0\n", "3\n", "not a number\n"])
    func manualCommandNeverPicksAnInstallationAfterAnInvalidChoice(_ choice: String) async throws {
        let rig = try ScriptRig()
        for name in ["Native.app", "Native Nightly.app"] {
            try rig.install("Applications/\(name)", helper: Self.manualHelper)
        }

        let result = try await rig.runManual(choice: choice)

        #expect(result.exitCode == 2)
        #expect(result.output.isEmpty)
        #expect(rig.helperArguments.isEmpty)
    }

    @Test func manualCommandReportsMissingAndOldInstallations() async throws {
        let rig = try ScriptRig()
        let missing = try await rig.runManual()
        #expect(missing.exitCode == LinkSSHPairing.ScriptStatus.notInstalled)
        #expect(missing.errorOutput.contains("Native was not found"))

        try rig.install(
            "home/Applications/Native Nightly.app", helper: "#!/bin/sh\necho started a host", version: "0.9.4")
        let old = try await rig.runManual()
        #expect(old.exitCode == LinkSSHPairing.ScriptStatus.tooOld)
        #expect(old.errorOutput.contains("Update it first"))
        #expect(old.output.trimmingCharacters(in: .whitespacesAndNewlines) == "0.9.4")
    }

    @Test func manualCommandHonorsAnExplicitInstallationWithShellCharacters() async throws {
        let rig = try ScriptRig()
        let installation = "Owner's Native $(false).app"
        try rig.install(installation, helper: Self.manualHelper)
        try rig.install("Applications/Native.app", helper: Self.manualHelper + "\necho wrong installation")

        let result = try await rig.runManual(installation: installation)

        #expect(result.succeeded)
        #expect(result.output == "fixture pairing link\n")
        #expect(!result.errorOutput.contains("Choose the installation"))
    }

    private static let manualHelper = """
        #!/bin/sh
        # \(LinkPairCommand.marker)
        printf '%s\\n' "$*" >&2
        echo 'fixture pairing link'
        """
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

    func runManual(choice: String = "", installation: String? = nil) async throws -> CommandResult {
        var environment = ProcessInfo.processInfo.environment
        environment["NATIVE_APP"] = installation.map { root.appending(path: $0).path }
        let command = LinkSSHPairing.manualCommand(
            grants: LinkGrants(manageHost: true, runCommands: true), appName: "Native.app",
            folders: ["Applications", "home/Applications"].map { LinkSSHPairing.quoted(root.appending(path: $0).path) })
        return try await LocalCommandRunner().run(
            Command(
                "/bin/sh", ["-c", command], environment: environment,
                standardInput: Data(choice.utf8), timeout: .seconds(10)))
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
