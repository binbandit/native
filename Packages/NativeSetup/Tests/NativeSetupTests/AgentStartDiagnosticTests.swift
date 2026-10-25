import Foundation
import Testing

@testable import NativeSetup

@Suite("A failed start's diagnostic and fix-it")
struct AgentStartDiagnosticTests {
    /// session/new's error `data` from codex-acp 2.2.2 with `approval_policy = "sometimes"`.
    static let unknownVariant = """
        failed to load configuration: /private/tmp/rd4-repro/home/config.toml:2:19: unknown variant `sometimes`, \
        expected one of `untrusted`, `on-failure`, `on-request`, `granular`, `never`

        Check /private/tmp/rd4-repro/home and project .codex directories, especially their config.toml files, \
        or any CODEX_CONFIG override.
        """
    /// The same adapter with an unterminated string on line 1.
    static let syntax = """
        failed to load configuration: /private/tmp/rd4-repro/home/config.toml:1:21: invalid basic string, \
        expected `"`

        Check /private/tmp/rd4-repro/home and project .codex directories, especially their config.toml files, \
        or any CODEX_CONFIG override.
        """

    @Test func readsTheAgentsLocation() throws {
        let diagnostic = try #require(AgentStartDiagnostic(output: Self.unknownVariant))
        #expect(diagnostic.path == "/private/tmp/rd4-repro/home/config.toml")
        #expect(diagnostic.line == 2)
        #expect(diagnostic.column == 19)
        #expect(diagnostic.fileName == "config.toml")
        #expect(diagnostic.message.hasPrefix("unknown variant `sometimes`"))
        #expect(!diagnostic.message.contains("Check"))
    }

    /// codex-acp 2.2.2's `data.details` when session/new brings MCP servers: the key, no file.
    static let withoutFile = """
        invalid configuration: unknown variant `on_request`, expected one of `untrusted`, `on-failure`, \
        `on-request`, `granular`, `never`
        in `approval_policy`
        """

    @Test func findsTheLineThatSetsTheNamedKey() throws {
        let files = [
            (path: "/home/.codex/config.toml", contents: "model = \"gpt-6.1-sol\"\napproval_policy = \"on_request\"\n"),
            (path: "/work/.codex/config.toml", contents: "# approval_policy = \"on_request\" was here\n"),
        ]
        let diagnostic = try #require(AgentStartDiagnostic(locating: Self.withoutFile, in: files))
        #expect(diagnostic.path == "/home/.codex/config.toml")
        #expect(diagnostic.line == 2)
        #expect(diagnostic.column == 19)
        #expect(diagnostic.fixIt == AgentStartFixIt(original: "on_request", replacement: "on-request"))
        #expect(diagnostic.fixIt?.apply(to: files[0].contents, at: diagnostic)?.contains("\"on-request\"") == true)
    }

    @Test func theAssignmentsValueIsChangedNotAComment() throws {
        let contents = "approval_policy = 'on_request' # previously \"on_request\"\n"
        let diagnostic = try #require(AgentStartDiagnostic(locating: Self.withoutFile, in: [("/a.toml", contents)]))
        #expect(diagnostic.column == 19)
        #expect(
            diagnostic.fixIt?.apply(to: contents, at: diagnostic)
                == "approval_policy = 'on-request' # previously \"on_request\"\n")
        // A valid value with the rejected one only in its comment isn't the line.
        let valid = "approval_policy = \"never\" # not \"on_request\"\n"
        #expect(AgentStartDiagnostic(locating: Self.withoutFile, in: [("/a.toml", valid)]) == nil)
    }

    @Test func overlappingDeclarationsNameOneFile() {
        let paths = AgentStartFile.settingsPaths(
            Self.codexSettings, home: "/fixture", environment: ["CODEX_HOME": "/fixture/.codex"], folder: "/project")
        #expect(paths == ["/fixture/.codex/config.toml", "/project/.codex/config.toml"])
    }

    @Test func aKeySetInTwoPlacesIsNotGuessed() {
        let line = "approval_policy = \"on_request\"\n"
        #expect(AgentStartDiagnostic(locating: Self.withoutFile, in: [("/a.toml", line), ("/b.toml", line)]) == nil)
        #expect(AgentStartDiagnostic(locating: Self.withoutFile, in: [("/a.toml", "model = \"x\"\n")]) == nil)
    }

    @Test func outputWithoutALocationClaimsNothing() {
        #expect(AgentStartDiagnostic(output: "Codex exited.\n\nerror: connection reset by peer") == nil)
        #expect(AgentStartDiagnostic(output: "Internal error") == nil)
    }

    @Test func noCloseValueOffersNoFix() throws {
        #expect(try #require(AgentStartDiagnostic(output: Self.unknownVariant)).fixIt == nil)
        #expect(try #require(AgentStartDiagnostic(output: Self.syntax)).fixIt == nil)
    }

    @Test(arguments: [
        ("xhigh", "high"), ("hgih", "high"), ("Medium", "medium"), ("on_request", "on-request"),
    ])
    func suggestsTheOneCloseValue(_ typed: String, _ expected: String) throws {
        let message = "unknown variant `\(typed)`, expected one of `minimal`, `low`, `medium`, `high`, `on-request`"
        #expect(AgentStartFixIt(message: message)?.replacement == expected)
    }

    @Test func aTieOffersNoFix() {
        #expect(AgentStartFixIt(message: "unknown variant `lo`, expected `low` or `log`") == nil)
    }

    @Test func fixChangesOnlyTheValue() throws {
        let contents = "model = \"gpt-6.1-sol\"\r\nmodel_reasoning_effort = \"xhigh\" # mine\r\n[mcp]\r\n"
        let diagnostic = AgentStartDiagnostic(
            path: "/tmp/config.toml", line: 2, column: 26, message: "unknown variant `xhigh`, expected `high`")
        let fixIt = try #require(diagnostic.fixIt)
        #expect(
            fixIt.apply(to: contents, at: diagnostic)
                == "model = \"gpt-6.1-sol\"\r\nmodel_reasoning_effort = \"high\" # mine\r\n[mcp]\r\n")
    }

    @Test func aChangedFileIsLeftAlone() {
        let fixIt = AgentStartFixIt(original: "xhigh", replacement: "high")
        let diagnostic = AgentStartDiagnostic(path: "/tmp/config.toml", line: 2, column: 26, message: "")
        #expect(fixIt.apply(to: "model = \"x\"\neffort = \"low\"\n", at: diagnostic) == nil)
        #expect(fixIt.apply(to: "a = \"xhigh\"\n", at: diagnostic) == nil)
    }

    @Test func excerptHidesCredentials() {
        let diagnostic = AgentStartDiagnostic(path: "/tmp/config.toml", line: 3, column: 10, message: "")
        let lines = diagnostic.excerpt(of: "x = 1\nexperimental_bearer_token = \"sk-live\"\nmodel = \"y\n")
        #expect(lines.map(\.number) == [2, 3])
        #expect(lines[0] == .init(number: 2, text: "experimental_bearer_token =", isRedacted: true))
        #expect(lines[1] == .init(number: 3, text: "model = \"y", isRedacted: false))
        #expect(AgentStartDiagnostic(path: "/tmp/c", line: 9, column: 1, message: "").excerpt(of: "x = 1").isEmpty)
    }

    @Test func excerptHidesCredentialsWithoutAKey() {
        let diagnostic = AgentStartDiagnostic(path: "/tmp/config.toml", line: 3, column: 1, message: "")
        let lines = diagnostic.excerpt(
            of:
                "url = \"https://fixture-user:fixture-pass@example.invalid\"\n\"Bearer abcdef0123\"\nmodel = \"ghp_0123456789abcdef\"\n"
        )
        // Line 1 isn't in the excerpt; lines 2 and 3 are hidden whole.
        #expect(lines.allSatisfy { $0.isRedacted && $0.text.isEmpty })
        let url = AgentStartDiagnostic(path: "/tmp/config.toml", line: 1, column: 1, message: "")
        #expect(
            url.excerpt(of: "https://fixture-user:fixture-pass@example.invalid\n") == [
                .init(number: 1, text: "", isRedacted: true)
            ])
        #expect(url.excerpt(of: "model = \"gpt-6.1-sol\"\n")[0].isRedacted == false)
    }

    static let codexSettings = ["$CODEX_HOME/config.toml", "~/.codex/config.toml", ".codex/config.toml"]

    @Test func settingsPathsExpandFromThePlugin() {
        let paths = AgentStartFile.settingsPaths(
            Self.codexSettings, home: "/Users/developer", environment: ["CODEX_HOME": "/opt/codex"],
            folder: "/Users/developer/Developer/native")
        #expect(
            paths == [
                "/opt/codex/config.toml", "/Users/developer/.codex/config.toml",
                "/Users/developer/Developer/native/.codex/config.toml",
            ])
        // An unset variable, or no task folder yet, names nothing.
        #expect(
            AgentStartFile.settingsPaths(Self.codexSettings, home: "/Users/developer", environment: [:], folder: nil)
                == ["/Users/developer/.codex/config.toml"])
    }

    @Test(arguments: [
        "/Users/developer/.git-credentials", "/Users/developer/.codex/auth.json",
        "/Users/developer/Library/Application Support/Firefox/Profiles/x/logins.json",
        "/Users/developer/.codex/../.ssh/config", "relative/config.toml",
    ])
    func onlyDeclaredSettingsFilesAreOpened(_ path: String) {
        let allowed = ["/Users/developer/.codex/config.toml"]
        #expect(!AgentStartFile.mayRead(path, allowed: allowed))
        #expect(AgentStartFile.read(path, allowed: allowed) == nil)
        #expect(AgentStartFile.mayRead("/Users/developer/.codex/config.toml", allowed: allowed))
        #expect(AgentStartFile.mayRead("/Users/developer/.codex/./config.toml", allowed: allowed))
    }

    @Test func aLinkToACredentialStoreIsNeverOpened() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "agent-start-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = folder.appending(path: ".git-credentials")
        let link = folder.appending(path: "config.toml")
        try Data("https://fixture-user:fixture-pass@example.invalid\n".utf8).write(to: store)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: store)
        // The link is where a settings file would be, but it leads to a credential store.
        let allowed = [link.path]
        #expect(!AgentStartFile.mayRead(link.path, allowed: allowed))
        #expect(AgentStartFile.read(link.path, allowed: allowed) == nil)
        let diagnostic = AgentStartDiagnostic(
            path: link.path, line: 1, column: 1, message: "unknown variant `hgih`, expected `high`")
        #expect(throws: AgentStartFile.Failure.unreadable("config.toml")) {
            try AgentStartFile.apply(
                AgentStartFixIt(original: "hgih", replacement: "high"), at: diagnostic, allowed: allowed)
        }
    }

    @Test func applyKeepsTheOriginalAndPermissions() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "agent-start-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let real = folder.appending(path: "dotfiles-config.toml")
        let link = folder.appending(path: "config.toml")
        let original = "model = \"gpt-6.1-sol\"\nmodel_reasoning_effort = \"xhigh\"\n"
        try Data(original.utf8).write(to: real)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: real.path)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let diagnostic = AgentStartDiagnostic(
            path: link.path, line: 2, column: 26,
            message: "unknown variant `xhigh`, expected one of `minimal`, `low`, `medium`, `high`")

        // A dotfiles setup: the declared settings file links to the real one.
        let allowed = [link.path]
        let backup = try AgentStartFile.apply(try #require(diagnostic.fixIt), at: diagnostic, allowed: allowed)

        #expect(try String(contentsOf: real, encoding: .utf8).contains("model_reasoning_effort = \"high\""))
        #expect(try String(contentsOf: URL(filePath: backup), encoding: .utf8) == original)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == real.path)
        let permissions = try FileManager.default.attributesOfItem(atPath: real.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
        #expect(throws: AgentStartFile.Failure.changed("config.toml")) {
            try AgentStartFile.apply(try #require(diagnostic.fixIt), at: diagnostic, allowed: allowed)
        }
    }
}
