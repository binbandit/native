import Foundation

/// How an action starts, in a terminal or in the background: which folder, which environment, and
/// for a terminal the command line that frames it so the terminal can report how it ended.
public struct ProjectActionLaunch: Hashable, Sendable {
    public let action: ProjectAction
    /// Where it runs.
    public let directory: URL
    /// What it's told about where it runs, with the names the repo's event scripts use.
    public let environment: [String: String]

    public init(_ action: ProjectAction, worktree: URL, project: URL) {
        self.action = action
        directory = action.directory.resolved(worktree: worktree, project: project)
        environment = [
            "NATIVE_PROJECT_PATH": project.path(percentEncoded: false),
            "NATIVE_WORKTREE_PATH": worktree.path(percentEncoded: false),
            "NATIVE_ACTION": action.name,
        ]
    }

    /// The command line a terminal tab runs, for `shell` (the user's terminal shell). It clears
    /// what `login(1)` printed ("Last login: …"), prints the command dimmed, marks its start and
    /// end with OSC 133 (the end carries the exit status, which the terminal reports as a finished
    /// command, since a login wrapper hides the shell's own exit status on the Mac), and runs it as
    /// a login, interactive shell would, so it sees what a command typed in a new tab sees.
    ///
    /// The terminal hands it to `bash -c`, so every word is single-quoted for bash.
    public func terminalCommand(shell: String) -> String {
        let assignments = environment.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
        let words = ["/usr/bin/env"] + assignments + ["/bin/sh", "-c", Self.frame, "sh", shell, action.command]
        return words.map(Self.quoted).joined(separator: " ")
    }

    /// The POSIX script around the command: `$1` is the shell, `$2` the command.
    static let frame = [
        #"printf '\033[H\033[2J\033[3J\033[2m$ %s\033[0m\n' "$2""#,
        #"printf '\033]133;C\007'"#,
        #""$1" -l -i -c "$2""#,
        "status=$?",
        // The status, and the cursor hidden: nothing more can be typed there.
        #"printf '\033]133;D;%d\007\033[?25l' "$status""#,
        #"exit "$status""#,
    ].joined(separator: "; ")

    /// `text` as one single-quoted shell word.
    static func quoted(_ text: String) -> String {
        "'\(text.replacingOccurrences(of: "'", with: #"'\''"#))'"
    }
}
