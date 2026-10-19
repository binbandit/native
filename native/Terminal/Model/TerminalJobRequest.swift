import Foundation

/// A command to run in a terminal tab of its own, in place of a shell (`TerminalStore.run(_:for:)`):
/// a project action, say. Running a request with the same key again reuses the tab.
struct TerminalJobRequest {
    /// Identifies the job across runs.
    let key: String
    /// The tab's name.
    let name: String
    /// What the user wrote, for the tab's notices.
    let command: String
    /// What the terminal runs: `command` framed so it reports its exit status with OSC 133
    /// (`ProjectActionLaunch.terminalCommand(shell:)`).
    let commandLine: String
    let directory: URL
}
