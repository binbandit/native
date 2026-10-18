import Foundation

/// The user's login shell, from the user database (what `dscl . -read ~ UserShell` shows) rather
/// than `$SHELL`, which an app opened from the Dock or Finder may not have. A host-backed terminal
/// resolves this on the host that runs it, not on the client.
enum TerminalLoginShell {
    static var current: String {
        guard let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell else {
            return ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        }
        let path = String(cString: shell)
        return path.isEmpty ? "/bin/zsh" : path
    }

    /// Whether `path` is a program this user can run.
    static func isRunnable(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && !isDirectory.boolValue
            && FileManager.default.isExecutableFile(atPath: path)
    }
}
