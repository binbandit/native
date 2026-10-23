import SwiftUI
import TaskScripts

/// How a task's new worktree is getting set up: the setup scripts running with their output and a
/// Stop, a question before the repository's own script runs the first time, the result, or a
/// failure with what failed, its exit code and last lines, and Retry or Skip.
struct TaskScriptSetupStrip: View {
    let run: TaskScriptRun
    let edit: (TaskScriptEditorSheet.Target) -> Void

    @Environment(TaskScriptCenter.self) private var center
    @State private var showsOutput = false

    var body: some View {
        TaskScriptStrip(
            isFailure: run.isFailure,
            onDismiss: run.state == .succeeded ? { center.dismiss(run) } : nil
        ) {
            glyph
        } content: {
            TaskScriptStripText(title: title, message: message)
            if showsOutput || run.isFailure {
                TaskScriptOutputView(output: run.output)
            }
            actions
                .padding(.top, DS.Space.xxs)
        }
    }

    @ViewBuilder private var glyph: some View {
        switch run.state {
        case .running:
            DotGridLoader(pattern: .settingUp)
                .foregroundStyle(.dsTextSecondary)
                .frame(width: TaskScriptMetrics.loader, height: TaskScriptMetrics.loader)
        case .awaitingApproval:
            Image(systemName: "questionmark.circle.fill")
                .foregroundStyle(Color.dsAttention)
        case .succeeded where run.baseNotice != nil && run.copyFailure == nil:
            Image(systemName: "info.circle")
                .foregroundStyle(Color.dsTextSecondary)
        case .succeeded where run.copyFailure != nil:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.dsWarning)
        case .succeeded, .skipped:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.dsSuccess)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.dsDanger)
        }
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: DS.Space.sm) {
            switch run.state {
            case .running:
                Button(showsOutput ? "Hide Output" : "Show Output") { showsOutput.toggle() }
                    .buttonStyle(.ds(.secondary))
                Button("Stop") { center.stop(run) }
                    .buttonStyle(.ds(.ghost))
                Button("Skip Setup") { center.skip(run) }
                    .buttonStyle(.ds(.ghost))
                    .help("Stops the setup script and sends your messages now")
            case .awaitingApproval:
                Button("Allow and Run") { center.allowRepositoryScripts(for: run) }
                    .buttonStyle(.ds(.primary))
                    .help("Lets this project's repository scripts run on this Mac from now on")
                Button("Show Script") { edit(.init(event: .setup, scope: .repository(project: run.projectRoot))) }
                    .buttonStyle(.ds(.secondary))
                Button(run.plan.scripts.isEmpty ? "Skip Setup" : "Run Without It") {
                    center.runWithoutRepositoryScript(run)
                }
                .buttonStyle(.ds(.ghost))
            case .failed(let failure):
                Button("Retry") { center.retry(run) }
                    .buttonStyle(.ds(.primary))
                Button("Skip Setup") { center.skip(run) }
                    .buttonStyle(.ds(.secondary))
                    .help("Sends your messages now, without what the script sets up")
                Button(failure.script.source == .repository ? "Show Script" : "Edit Script…") {
                    edit(.init(event: .setup, scope: .init(failure.script.source, project: run.projectRoot)))
                }
                .buttonStyle(.ds(.ghost))
            case .succeeded, .skipped:
                if !run.output.isEmpty {
                    Button(showsOutput ? "Hide Output" : "Show Output") { showsOutput.toggle() }
                        .buttonStyle(.ds(.ghost))
                }
            }
        }
    }

    // MARK: - Text

    private var title: String {
        switch run.state {
        case .running: "Setting up the worktree"
        case .awaitingApproval: "This repository has a setup script"
        case .succeeded where run.plan.scripts.isEmpty && run.copyFailure != nil:
            "Couldn't copy the project's env files"
        case .succeeded, .skipped:
            (run.duration ?? 0) < 1 ? "Worktree set up" : "Worktree set up in \(DSFormat.duration(run.duration ?? 0))"
        case .failed(let failure): "\(failure.script.name) \(failure.result.outcome.phrase)"
        }
    }

    private var message: String? {
        var parts: [String] = []
        switch run.state {
        case .running:
            let script = run.current.map { "Running \($0.name.lowercasedFirst)." } ?? "Starting the setup script."
            parts.append("\(script) Messages you send wait until it's done.")
        case .awaitingApproval:
            let path = run.plan.awaitingApproval?.event.repositoryPath ?? TaskScriptEvent.setup.repositoryPath
            parts.append(
                "\(run.projectRoot.lastPathComponent) commits \(path) to run in each new worktree. Whoever commits to the repository can change it, so Native asks once before running its scripts on this Mac. Your messages wait until you choose."
            )
        case .failed(let failure):
            parts.append(TaskScriptFailureText.detail(failure, ofRun: run))
        case .succeeded, .skipped:
            break
        }
        if let baseNotice = run.baseNotice { parts.append(baseNotice) }
        if !run.copiedFiles.isEmpty {
            let files = run.copiedFiles.count == 1 ? run.copiedFiles[0] : "\(run.copiedFiles.count) env files"
            parts.append("Copied \(files) from the project.")
        }
        if let copyFailure = run.copyFailure {
            parts.append("Couldn't copy the project's env files: \(copyFailure)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

extension String {
    /// "The project's setup script" as "the project's setup script", for the middle of a sentence.
    fileprivate var lowercasedFirst: String {
        prefix(1).lowercased() + dropFirst()
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Setup strip") {
    DSPreviewPair {
        VStack(spacing: DS.Space.lg) {
            TaskScriptSetupStrip(run: TaskScriptsPreviewFixtures.running, edit: { _ in })
            TaskScriptSetupStrip(run: TaskScriptsPreviewFixtures.awaitingApproval, edit: { _ in })
            TaskScriptSetupStrip(run: TaskScriptsPreviewFixtures.succeeded, edit: { _ in })
            TaskScriptSetupStrip(run: TaskScriptsPreviewFixtures.failed, edit: { _ in })
        }
        .frame(width: 720)
    }
    .environment(TaskScriptsPreviewFixtures.center())
}
#endif

#if DEBUG
#Preview("Worktree - Local base after failed fetch") {
    DSPreviewPair {
        TaskScriptSetupStrip(run: TaskScriptWorktreePreviewFixtures.localBase, edit: { _ in })
            .frame(width: 560)
    }
    .environment(TaskScriptWorktreePreviewFixtures.center())
}
#endif
