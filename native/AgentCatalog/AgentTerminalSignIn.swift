import ACP
import Foundation

/// Signing in to an agent from a terminal, for agents that can't sign in over ACP: ones whose
/// manifest gives a `setup.signIn` command (OpenCode's `authenticate` succeeds without signing in;
/// Copilot's answers "Authentication required"), and ACP methods marked terminal-only.
struct AgentTerminalSignIn: Identifiable {
    let id = UUID()
    let agent: AgentDefinition
    /// What runs in the terminal, as a shell would read it.
    let command: String
    /// Whether to start a session with the agent once signed in: the user was starting one when it
    /// asked them to sign in.
    let startsSession: Bool

    /// How to sign in to `agent` with `method` from a terminal; nil when the method works over ACP.
    init?(agent: AgentDefinition, method: AuthMethod?, startsSession: Bool) {
        if let signIn = agent.manifest.setup?.signIn {
            command = signIn
        } else {
            switch method?.terminal {
            case .command(let executable, let arguments):
                command = ([executable] + arguments).map(Self.quoted).joined(separator: " ")
            case .agent(let arguments):
                command = ([agent.manifest.command] + agent.manifest.args + arguments).map(Self.quoted)
                    .joined(separator: " ")
            case nil:
                return nil
            }
        }
        self.agent = agent
        self.startsSession = startsSession
    }

    /// The command as the terminal runs it: through the user's login shell, so it finds the same
    /// PATH and environment the agent launched with.
    var shellCommand: String {
        let shell = getpwuid(getuid()).flatMap { $0.pointee.pw_shell }.map { String(cString: $0) } ?? "/bin/zsh"
        return [shell, "-l", "-i", "-c", command].map(Self.quoted).joined(separator: " ")
    }

    /// `word` as one shell word.
    static func quoted(_ word: String) -> String {
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_./=@:+,%"))
        guard !word.isEmpty, word.unicodeScalars.allSatisfy(safe.contains) else {
            return "'" + word.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
        return word
    }
}
