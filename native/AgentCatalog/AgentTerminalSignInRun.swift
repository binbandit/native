import Foundation
import Observation
import Terminal

/// One run of an agent's sign-in command in a terminal of its own, and how it ended. The terminal
/// only reports that its process exited, so the command records its exit code in a file beside it.
@Observable
final class AgentTerminalSignInRun {
    enum Outcome: Equatable {
        case running
        case succeeded
        /// Exited with an error, or before it really started; the code when it got that far.
        case failed(code: Int32?)
    }

    private let panel: TerminalPanelModel
    @ObservationIgnored private let statusFile: URL
    /// The last outcome seen, for after the user closes the ended terminal with a key press.
    @ObservationIgnored private var lastOutcome = Outcome.running

    init(request: AgentTerminalSignIn, terminals: TerminalStore) {
        statusFile = FileManager.default.temporaryDirectory.appending(path: "native-sign-in-\(request.id).status")
        let quotedFile = AgentTerminalSignIn.quoted(statusFile.path(percentEncoded: false))
        let script = "\(request.shellCommand); echo $? > \(quotedFile)"
        panel = terminals.standalonePanel(
            running: "/bin/sh -c \(AgentTerminalSignIn.quoted(script))", in: .homeDirectory)
        panel.newTab()
    }

    /// The running (or ended) terminal; nil once it's closed or when it couldn't start.
    var surface: TerminalSurface? {
        panel.tabs.selected.flatMap { panel.surface(for: $0.id) }
    }

    var status: TerminalStatus? {
        panel.tabs.selected?.status
    }

    var outcome: Outcome {
        switch status {
        case .running: lastOutcome = .running
        case .exited: lastOutcome = exitCode == 0 ? .succeeded : .failed(code: exitCode)
        case .failedToStart: lastOutcome = .failed(code: exitCode)
        case nil: break
        }
        return lastOutcome
    }

    /// Runs the command again, in the same terminal if it's still open.
    func restart() {
        try? FileManager.default.removeItem(at: statusFile)
        lastOutcome = .running
        if let id = panel.tabs.selected?.id {
            panel.restart(id)
        } else {
            panel.newTab()
        }
        panel.focusSelected()
    }

    /// Ends the command, if it's still running, and its terminal.
    func end() {
        panel.closeAll()
        try? FileManager.default.removeItem(at: statusFile)
    }

    private var exitCode: Int32? {
        (try? String(contentsOf: statusFile, encoding: .utf8))
            .flatMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }
}
