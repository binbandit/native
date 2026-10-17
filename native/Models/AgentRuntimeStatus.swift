/// How starting an agent went, with what views need to show it, so they don't each switch over it.
enum AgentRuntimeStatus: Equatable {
    case starting
    case ready
    /// The agent's command isn't on the user's PATH, so it was never launched.
    case notInstalled(command: String)
    /// It launched but stopped or never got going; the message ends with what it logged.
    case failed(String)

    /// How much the status needs the user, for picking a color or glyph.
    enum Severity {
        case progress, ok, attention, problem
    }

    var label: String {
        switch self {
        case .starting: "Starting…"
        case .ready: "Ready"
        case .notInstalled: "Not installed"
        case .failed: "Stopped"
        }
    }

    var severity: Severity {
        switch self {
        case .starting: .progress
        case .ready: .ok
        case .notInstalled: .attention
        case .failed: .problem
        }
    }

    /// What to tell the user beyond the label: how to fix a missing command, or why it stopped.
    var guidance: String? {
        switch self {
        case .starting, .ready: nil
        case .notInstalled(let command):
            "Native couldn't find `\(command)` on your PATH. Install it, then choose Retry."
        case .failed(let message): message
        }
    }

    /// Whether starting the agent again could help.
    var canRetry: Bool {
        switch self {
        case .starting, .ready: false
        case .notInstalled, .failed: true
        }
    }
}
