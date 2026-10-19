import Exec
import Foundation

/// One script that runs for an event, and where it comes from.
public struct TaskScript: Hashable, Sendable {
    public enum Source: Hashable, Sendable, CaseIterable {
        /// Settings ▸ Scripts: the user's, for every project.
        case global
        /// The project's own, kept in Native's settings on this Mac.
        case project
        /// Committed to the project's repository, at the event's `repositoryPath`.
        case repository
    }

    public var event: TaskScriptEvent
    public var source: Source
    public var text: String

    public init(event: TaskScriptEvent, source: Source, text: String) {
        self.event = event
        self.source = source
        self.text = text
    }

    /// The command that runs the script in `directory`, with `environment` (the login shell's,
    /// plus the task's `NATIVE_*` variables). A script that starts with `#!` runs with the interpreter
    /// it names, so a committed file works whatever each person's shell is; any other script runs
    /// with the user's shell, `SHELL` in `environment`. Its output ends when it exits, so a server it
    /// leaves running in the background doesn't keep it going.
    public func command(in directory: String, environment: [String: String], timeout: Duration?) -> Command {
        let (executable, arguments, input) = invocation(shell: environment["SHELL"])
        return Command(
            executable, arguments, in: directory, environment: environment, standardInput: input, timeout: timeout,
            outputEndsAtExit: true)
    }

    func invocation(shell: String?) -> (executable: String, arguments: [String], input: Data?) {
        if let interpreter = Self.interpreter(of: text), let program = interpreter.first {
            // The script goes into a temporary file the interpreter runs, removed when it's done. Its
            // standard input is at its end by then, like a terminal's with nothing typed.
            let wrapper =
                #"f=$(mktemp "${TMPDIR:-/tmp}/native-script.XXXXXX") || exit 70; trap 'rm -f "$f"' EXIT; trap 'exit 143' TERM INT HUP; cat > "$f"; "$@" "$f""#
            return ("/bin/sh", ["-c", wrapper, "sh", program] + interpreter.dropFirst(), Data(text.utf8))
        }
        let shell = shell.flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/sh"
        return (shell, ["-c", text], nil)
    }

    /// The `#!` line's interpreter and arguments, split on whitespace as macOS does:
    /// `#!/usr/bin/env bash -e` is `["/usr/bin/env", "bash", "-e"]`.
    static func interpreter(of text: String) -> [String]? {
        guard text.hasPrefix("#!") else { return nil }
        let line = text.dropFirst(2).prefix { !$0.isNewline }
        let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
        return parts.isEmpty ? nil : parts
    }
}
