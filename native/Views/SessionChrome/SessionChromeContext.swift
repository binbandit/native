#if DEBUG
import ACP
import Foundation
import Git
import GitHub
import ProjectActions
import Terminal

/// What a tool has to say about the task right now, as data: "2 files +12 −3", "Dev :3000",
/// "Xcode". A tool whose fact isn't live stays out of sight in the contextual places.
struct SessionChromeFact {
    enum Tone {
        case quiet, running, failed
    }

    var text: String
    var tone = Tone.quiet
    var diff: LineStats?
    /// Whether there's something to see now (changes made, a shell open, an action running).
    var isLive: Bool
}

/// The models one session screen's tools read and act on.
struct SessionChromeContext {
    let session: SessionModel
    let repository: GitRepositoryModel
    let terminals: TerminalStore
    let runner: ProjectActionRunner
    let target: ProjectActionTarget?
    let openIn: OpenInLocation
    let gitHub: GitHubModel
    /// Which changes the Changes pane shows; the turn card's Review points it at the turn.
    let changesReview: GitChangesReview

    var terminal: TerminalPanelModel {
        terminals.panel(for: session)
    }

    var branchName: String? {
        guard case .branch(let name)? = repository.branch?.head else { return nil }
        return name
    }

    var branchReference: BranchReference? {
        branchName.map { BranchReference(directory: session.cwd, branch: $0) }
    }

    func fact(for tool: SessionChromeTool) -> SessionChromeFact {
        switch tool {
        case .changes:
            let count = repository.changes.count
            return SessionChromeFact(
                text: count == 0 ? "No changes" : count == 1 ? "1 file" : "\(count) files",
                diff: count == 0 ? nil : repository.totals, isLive: count > 0)
        case .terminal:
            let shells = terminal.tabs.tabs.count(where: { $0.job == nil })
            return SessionChromeFact(text: shells > 1 ? "\(shells) terminals" : "Terminal", isLive: shells > 0)
        case .run:
            return runFact
        case .agents:
            let count = session.state.subagents.count
            return SessionChromeFact(text: count == 1 ? "1 subagent" : "\(count) subagents", isLive: count > 0)
        case .pullRequest:
            if let branch = branchReference, let pullRequest = gitHub.pullRequest(for: branch) {
                return SessionChromeFact(text: "#\(pullRequest.number)", isLive: true)
            }
            return SessionChromeFact(text: branchName ?? "No branch", isLive: false)
        case .openIn:
            let app = OpenInModel.shared.defaultApp(for: openIn)
            return SessionChromeFact(text: app?.name ?? "Copy Path", isLive: true)
        }
    }

    /// A tool's name in a tab; a run's tab names what's running ("Dev :4173").
    func tabTitle(for tool: SessionChromeTool) -> String {
        let fact = fact(for: tool)
        return tool == .run && fact.isLive ? fact.text : tool.title
    }

    private var runFact: SessionChromeFact {
        guard let target else { return SessionChromeFact(text: "Run", isLive: false) }
        let running = runner.running(in: target)
        if let first = running.first {
            let port = Self.port(in: first.command).map { " :\($0)" } ?? ""
            return SessionChromeFact(
                text: running.count == 1 ? "\(first.name)\(port)" : "\(running.count) running", tone: .running,
                isLive: true)
        }
        if let last = runner.store.lastRunAction(in: target.project),
            runner.state(of: last, in: target)?.hasFailed == true
        {
            return SessionChromeFact(text: "\(last.name) failed", tone: .failed, isLive: true)
        }
        return SessionChromeFact(text: "Run", isLive: false)
    }

    /// The port a dev-server command names, as a rough guess for the prototype.
    private static func port(in command: String) -> Substring? {
        command.firstMatch(of: /\b(\d{4,5})\b/)?.1
    }
}
#endif
