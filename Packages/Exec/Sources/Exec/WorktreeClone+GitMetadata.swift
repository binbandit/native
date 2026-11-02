#if os(macOS)
import Darwin
import Foundation

extension WorktreeClone {
    static func validateGitMetadata(_ directory: Int32) throws {
        // A directory-form gitdir can still redirect writes through these ordinary files.
        for name in ["commondir", "config.worktree"] {
            var info = stat()
            guard fstatat(directory, name, &info, AT_SYMLINK_NOFOLLOW) != 0, errno == ENOENT else {
                throw CommandError.refused("A cached checkout uses redirected git metadata.")
            }
        }
        let config = openat(directory, "config", O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        if config < 0, errno == ENOENT { return }
        guard config >= 0 else { throw CommandError.refused("A cached checkout has unsafe git configuration.") }
        defer { close(config) }
        var info = stat()
        guard fstat(config, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
            throw CommandError.refused("A cached checkout has unsafe git configuration.")
        }
        // Let Git parse quoting, case and section syntax. No includes or user configuration are read.
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = ["config", "--no-includes", "--file", "-", "--name-only", "--list"]
        process.environment = ["PATH": "/usr/bin:/bin", "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null"]
        process.standardInput = FileHandle(fileDescriptor: config, closeOnDealloc: false)
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let keys = String(decoding: data, as: UTF8.self).lowercased().split(separator: "\n")
        guard process.terminationStatus == 0,
            !keys.contains(where: {
                $0 == "core.worktree" || $0 == "extensions.worktreeconfig"
                    || $0.hasPrefix("include.") || $0.hasPrefix("includeif.")
            })
        else { throw CommandError.refused("A cached checkout uses redirected git configuration.") }
    }
}
#endif
