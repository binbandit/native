#if os(macOS)
import Foundation
import Testing

@testable import ACP

@Suite struct NpxLaunchTests {
    /// A fake npm cache holding one npx install of `name@version` with the given `bin` field.
    private func cache(name: String, version: String, bin: String) throws -> URL {
        let cache = FileManager.default.temporaryDirectory.appending(path: "npx-\(UUID().uuidString)")
        let launch = try #require(
            NpxLaunch(AgentCommand(executable: "npx", arguments: ["\(name)@\(version)"], environment: ["npm_config_cache": cache.path])))
        let modules = launch.folder.appending(path: "node_modules")
        let package = modules.appending(path: name)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try Data(#"{"name": "\#(name)", "version": "\#(version)", "bin": \#(bin)}"#.utf8)
            .write(to: package.appending(path: "package.json"))
        let binaries = modules.appending(path: ".bin")
        try FileManager.default.createDirectory(at: binaries, withIntermediateDirectories: true)
        for binary in ["codex-acp", "helper"] {
            let file = binaries.appending(path: binary)
            FileManager.default.createFile(atPath: file.path, contents: Data("#!/bin/sh\n".utf8))
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        }
        return cache
    }

    private func npx(_ arguments: [String], cache: URL) -> AgentCommand {
        AgentCommand(
            executable: "npx", arguments: arguments,
            environment: ["npm_config_cache": cache.path, "PATH": "/usr/bin"],
            workingDirectory: URL(filePath: "/tmp"))
    }

    @Test func folderMatchesNpmsHash() throws {
        // npm 11 put `npx @agentclientprotocol/codex-acp@2.2.2` in this folder.
        let launch = try #require(
            NpxLaunch(
                AgentCommand(
                    executable: "/opt/homebrew/bin/npx", arguments: ["--yes", "@agentclientprotocol/codex-acp@2.2.2"],
                    environment: ["HOME": "/Users/me"])))
        #expect(launch.folder.path(percentEncoded: false) == "/Users/me/.npm/_npx/4a4ca55c38a52b9f/")
    }

    @Test func runsTheInstalledBinaryDirectly() throws {
        let cache = try cache(name: "@agentclientprotocol/codex-acp", version: "2.2.2", bin: #"{"codex-acp": "dist/index.js"}"#)
        let command = npx(["--yes", "@agentclientprotocol/codex-acp@2.2.2", "--flag"], cache: cache).skippingNpx()

        #expect(command.executable.hasSuffix("/node_modules/.bin/codex-acp"))
        #expect(command.arguments == ["--flag"])
        #expect(command.environment["PATH"]?.hasSuffix("/node_modules/.bin:/usr/bin") == true)
        #expect(command.workingDirectory == URL(filePath: "/tmp"))
    }

    @Test func picksTheBinaryNamedAfterThePackage() throws {
        let cache = try cache(
            name: "@agentclientprotocol/codex-acp", version: "2.2.2",
            bin: #"{"helper": "dist/helper.js", "codex-acp": "dist/index.js"}"#)
        let command = npx(["-y", "@agentclientprotocol/codex-acp@2.2.2"], cache: cache).skippingNpx()
        #expect(command.executable.hasSuffix("/.bin/codex-acp"))
    }

    @Test func leavesEverythingElseToNpx() throws {
        let cache = try cache(name: "@agentclientprotocol/codex-acp", version: "2.2.2", bin: #""dist/index.js""#)
        let unchanged = [
            // Not installed at this version, a range, a tag, other options, not npx at all.
            npx(["--yes", "@agentclientprotocol/codex-acp@2.2.3"], cache: cache),
            npx(["--yes", "@agentclientprotocol/codex-acp@^2.2.2"], cache: cache),
            npx(["--yes", "@agentclientprotocol/codex-acp@latest"], cache: cache),
            npx(["--yes", "@agentclientprotocol/codex-acp"], cache: cache),
            npx(["--package", "x", "@agentclientprotocol/codex-acp@2.2.2"], cache: cache),
            AgentCommand(executable: "codex-acp", arguments: [], environment: ["npm_config_cache": cache.path]),
        ]
        for command in unchanged {
            #expect(command.skippingNpx() == command)
        }
    }

    @Test func aStringBinIsNamedAfterThePackage() throws {
        let cache = try cache(name: "@agentclientprotocol/codex-acp", version: "2.2.2", bin: #""dist/index.js""#)
        let command = npx(["@agentclientprotocol/codex-acp@2.2.2"], cache: cache).skippingNpx()
        #expect(command.executable.hasSuffix("/.bin/codex-acp"))
    }
}
#endif
