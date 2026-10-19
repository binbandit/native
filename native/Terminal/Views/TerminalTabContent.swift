import SwiftUI
import Terminal

/// The selected tab: its terminal, with what happened laid over it when the shell ended, or the
/// state that replaces it when there's no terminal to show.
struct TerminalTabContent: View {
    let panel: TerminalPanelModel
    let tab: TerminalTabList.Tab
    /// The terminal's background opacity, which the strip under a job's output matches.
    let backgroundOpacity: Double
    @Environment(SettingsPresentation.self) private var settings

    var body: some View {
        switch tab.status {
        case .failedToStart(.directoryMissing) where tab.job != nil:
            let folder = panel.jobDirectory(of: tab.id)?.abbreviatedPath ?? "Its folder"
            ErrorState(
                "“\(tab.displayTitle)” couldn't start",
                suggestion: "\(folder) doesn't exist in this task's folder. Change the action's folder, or "
                    + "check out the branch that has it.",
                primary: .init("Try Again") { panel.rerunJob(in: tab.id) },
                secondary: .init("Close Tab") { panel.close(tab.id) },
                layout: .pane
            )
        case .failedToStart(.directoryMissing):
            ErrorState(
                "This task's folder is gone",
                suggestion: "\(panel.workingDirectory.abbreviatedPath) no longer exists, so the terminal can't "
                    + "start there.",
                primary: .init("Open in Home Folder") { panel.restart(tab.id, in: .homeDirectory) },
                secondary: .init("Close Tab") { panel.close(tab.id) },
                layout: .pane
            )
        case .failedToStart(.shellNotFound(let path)):
            ErrorState(
                "\(path) isn't there",
                suggestion: "The shell this terminal runs can't be found or run. Open this tab with "
                    + "\(TerminalShell.fallback) instead, or choose another shell in Settings.",
                primary: .init("Use \(TerminalShell.fallback)") {
                    panel.restart(tab.id, shell: TerminalShell.fallback)
                },
                secondary: .init("Choose Shell…") { settings.open(.terminal) },
                layout: .pane
            )
        case .failedToStart(.engineFailed):
            ErrorState(
                "The terminal couldn't start",
                suggestion: "Try again. If it keeps failing, quit and reopen Native.",
                primary: .init("Try Again") { panel.restart(tab.id) },
                secondary: .init("Close Tab") { panel.close(tab.id) },
                layout: .pane
            )
        case .running, .exited, .failedToStart(.exitedImmediately):
            // One branch for every state with a terminal on screen, so the terminal view keeps its
            // identity (and keyboard focus) when its shell ends. A job's ending goes under its
            // output rather than over it, since its last lines are usually the summary.
            VStack(spacing: 0) {
                surface.overlay(alignment: .bottom) {
                    if tab.job == nil {
                        shellOutcome.padding(DS.Space.md)
                    }
                }
                if let job = tab.job, let outcome = job.outcome {
                    TerminalJobOutcomeBanner(job: job, outcome: outcome) { panel.rerunJob(in: tab.id) }
                        .padding(DS.Space.md)
                        .background(.dsSurfaceSunken.opacity(backgroundOpacity))
                }
            }
        }
    }

    /// What happened to the shell, over its last output.
    @ViewBuilder private var shellOutcome: some View {
        switch tab.status {
        case .exited:
            NoticeBanner(
                tone: .info,
                systemImage: "checkmark.circle",
                title: "The shell exited",
                detail: "Press any key to close this tab, or start a new shell here."
            ) {
                Button("Restart Shell") { panel.restart(tab.id) }
                    .buttonStyle(.ds(.secondary))
            }
        case .failedToStart:
            ErrorState(
                "The shell didn't start",
                suggestion: "It quit as soon as it launched; its output is above. Check your shell and its "
                    + "startup files, or open this tab with \(TerminalShell.fallback) for now.",
                primary: .init("Try Again") { panel.restart(tab.id) },
                secondary: .init("Use \(TerminalShell.fallback)") {
                    panel.restart(tab.id, shell: TerminalShell.fallback)
                }
            )
        case .running:
            EmptyView()
        }
    }

    @ViewBuilder private var surface: some View {
        #if os(macOS)
        if let surface = panel.surface(for: tab.id) {
            TerminalSurfaceHost(surface: surface)
        }
        #endif
    }
}
