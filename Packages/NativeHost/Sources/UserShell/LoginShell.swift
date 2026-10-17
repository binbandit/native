#if os(macOS)
import Foundation
import os

/// Processes started by launchd (the Finder, the Dock, a login item) get a bare environment, while
/// agents expect what a terminal has: the user's PATH (node, claude, git), API keys, and so on. So
/// ask the user's login shell for its environment, the same way a new terminal tab would build it.
///
/// The one copy for Native: the host launches agents with it, and the app runs the user's own tools
/// (git, gh) with it.
public enum LoginShell {
    private static let logger = Logger(subsystem: "Native", category: "LoginShell")

    /// Variables describing the shell process itself, which would be wrong for anything we launch.
    private static let shellOnlyVariables: Set = ["PWD", "OLDPWD", "SHLVL", "_"]

    /// What `login(1)` would hand a fresh shell. Starting from this, rather than our own environment,
    /// keeps things like Xcode's debugging variables from leaking into agents.
    private static let inheritedVariables = ["HOME", "USER", "LOGNAME", "TMPDIR", "SSH_AUTH_SOCK", "LANG", "__CF_USER_TEXT_ENCODING"]

    public static func environment() async -> [String: String] {
        let shell = userShell()
        do {
            return try await capture(shell: shell)
        } catch {
            logger.error("Couldn't read the environment of \(shell, privacy: .public): \(error)")
            return ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("DYLD_") }
        }
    }

    private static func userShell() -> String {
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell {
            return String(cString: shell)
        }
        return ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    }

    @concurrent
    private static func capture(shell: String) async throws -> [String: String] {
        // Markers fence the output off from anything the shell's startup files print.
        let marker = "__NATIVE_ENV_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))__"
        let process = Process()
        process.executableURL = URL(filePath: shell)
        // Interactive and login, since PATH setup commonly lives in either kind of startup file.
        process.arguments = ["-i", "-l", "-c", "printf '%s' \(marker); /usr/bin/env -0; printf '%s' \(marker)"]
        let current = ProcessInfo.processInfo.environment
        process.environment = current.filter { inheritedVariables.contains($0.key) }.merging(["SHELL": shell]) { $1 }
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        try process.run()

        // A broken startup file shouldn't hang whoever asked.
        let timeout = Task {
            try await Task.sleep(for: .seconds(10))
            process.terminate()
        }
        defer { timeout.cancel() }

        // Read until the closing marker rather than EOF: background jobs started by the shell's
        // startup files can hold the pipe open long after the shell exits.
        var output = Data()
        let markerData = Data(marker.utf8)
        while true {
            let chunk = stdout.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            output.append(chunk)
            if let first = output.range(of: markerData), output.range(of: markerData, in: first.upperBound..<output.endIndex) != nil {
                break
            }
        }

        let sections = String(decoding: output, as: UTF8.self).components(separatedBy: marker)
        guard sections.count >= 3 else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSDebugDescriptionErrorKey: "The shell exited without printing its environment"])
        }
        var environment: [String: String] = [:]
        for entry in sections[1].split(separator: "\0") {
            guard let separator = entry.firstIndex(of: "=") else { continue }
            let key = String(entry[..<separator])
            guard !shellOnlyVariables.contains(key) else { continue }
            environment[key] = String(entry[entry.index(after: separator)...])
        }
        return environment
    }
}
#endif
