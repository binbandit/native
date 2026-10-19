import SwiftUI
import TaskScripts

/// The status bar's quiet log of task scripts: the selected task's runs, newest first, and any
/// teardown or task-deleted script that failed for a task no longer on screen. It shows only when
/// there's something in it; a running script shows a loader, a failure a red dot.
struct TaskScriptsStatusItem: StatusBarItem {
    let center: TaskScriptCenter
    /// The selected task's folder.
    let folder: () -> URL?
    /// Opens Settings ▸ Scripts.
    let onManage: () -> Void

    let id = "task-scripts"
    let title = "Scripts"
    let placement = StatusBarPlacement.trailing
    let order = 35

    var content: some View {
        TaskScriptsStatusSegment(center: center, folder: folder(), onManage: onManage)
    }
}

private struct TaskScriptsStatusSegment: View {
    let center: TaskScriptCenter
    let folder: URL?
    let onManage: () -> Void

    var body: some View {
        let runs = folder.map { center.runs(in: $0).reversed() } ?? []
        let departed = center.departedFailures.filter { run in !runs.contains { $0 === run } }
        let isRunning = runs.contains(where: \.isRunning)
        let failures = runs.count { $0.isFailure && !$0.isDismissed } + departed.count
        if !runs.isEmpty || !departed.isEmpty {
            StatusBarSegment(
                help: help(isRunning: isRunning, failures: failures), accessibilityLabel: "Scripts",
                accessibilityValue: help(isRunning: isRunning, failures: failures)
            ) {
                HStack(spacing: DS.Space.sm) {
                    if isRunning {
                        DotGridLoader(pattern: .typing)
                            .frame(width: TaskScriptMetrics.loader, height: TaskScriptMetrics.loader)
                    } else {
                        StatusBarGlyph("terminal")
                    }
                    Text("Scripts")
                    if failures > 0 {
                        StatusDot(color: .dsDanger)
                    }
                }
            } details: {
                TaskScriptLogPanel(runs: Array(runs), departed: departed, onManage: onManage)
            }
        }
    }

    private func help(isRunning: Bool, failures: Int) -> String {
        if isRunning { return "A task script is running. Click for its output." }
        if failures > 0 { return failures == 1 ? "A task script failed." : "\(failures) task scripts failed." }
        return "The task's scripts ran. Click for their output."
    }
}

/// The log: each run with its event, outcome, time and output, and Retry, Stop or Dismiss.
struct TaskScriptLogPanel: View {
    let runs: [TaskScriptRun]
    let departed: [TaskScriptRun]
    let onManage: () -> Void

    var body: some View {
        PopoverPanel(title: "Scripts", systemImage: "terminal", width: TaskScriptMetrics.logWidth) {
            Button("Settings…", action: onManage)
                .buttonStyle(.ds(.ghost, size: .small))
        } content: {
            CappedHeightScrollView(maxHeight: TaskScriptMetrics.logMaxHeight) {
                VStack(alignment: .leading, spacing: 0) {
                    if !runs.isEmpty {
                        section("This task", runs)
                    }
                    if !departed.isEmpty {
                        section("Archived and deleted tasks", departed)
                    }
                }
            }
        }
    }

    private func section(_ title: String, _ runs: [TaskScriptRun]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.dsCaptionMedium)
                .foregroundStyle(.dsTextTertiary)
                .padding(.horizontal, DS.Space.lg)
                .padding(.top, DS.Space.md)
                .padding(.bottom, DS.Space.xs)
            ForEach(runs) { run in
                TaskScriptLogRow(run: run)
                SeparatorLine()
            }
        }
    }
}

/// One run in the log.
private struct TaskScriptLogRow: View {
    let run: TaskScriptRun

    @Environment(TaskScriptCenter.self) private var center
    @State private var showsOutput = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.sm) {
                glyph
                    .frame(width: TaskScriptMetrics.loader)
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(title)
                        .font(.dsBodyMedium)
                        .foregroundStyle(.dsTextPrimary)
                    Text(subtitle)
                        .font(.dsCaption)
                        .foregroundStyle(.dsTextSecondary)
                }
                Spacer(minLength: DS.Space.md)
                actions
            }
            if showsOutput || run.isFailure {
                TaskScriptOutputView(
                    output: run.output, maxHeight: TaskScriptMetrics.logOutputMaxHeight,
                    lines: showsOutput ? nil : TaskScriptMetrics.failureLines)
            }
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.vertical, DS.Space.md)
    }

    @ViewBuilder private var glyph: some View {
        switch run.state {
        case .running:
            DotGridLoader(pattern: .settingUp)
                .foregroundStyle(.dsTextSecondary)
                .frame(width: TaskScriptMetrics.loader, height: TaskScriptMetrics.loader)
        case .awaitingApproval:
            Image(systemName: "questionmark.circle.fill").foregroundStyle(Color.dsAttention)
        case .succeeded:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.dsSuccess)
        case .skipped:
            Image(systemName: "minus.circle").foregroundStyle(.dsTextTertiary)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.dsDanger)
        }
    }

    private var title: String {
        switch run.state {
        case .failed(let failure): "\(failure.script.name) \(failure.result.outcome.phrase)"
        case .running: "\(run.event.title) script running"
        case .awaitingApproval: "\(run.event.title) script waiting for you"
        case .skipped: "\(run.event.title) script skipped"
        case .succeeded: "\(run.event.title) script finished"
        }
    }

    private var subtitle: String {
        let sources = run.plan.scripts.map(\.source.label).joined(separator: " then ")
        let when = DSFormat.time(run.startedAt, now: .now)
        let duration = run.duration.map { " · took \(DSFormat.duration($0))" } ?? ""
        let place = run.event == .teardown || run.event == .taskDeleted ? " · \(run.folder.lastPathComponent)" : ""
        return [sources, "\(when)\(duration)\(place)"].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: DS.Space.xs) {
            if run.isRunning {
                Button("Stop") { center.stop(run) }
                    .buttonStyle(.ds(.ghost, size: .small))
            } else if run.isFailure, !run.isDismissed {
                if run.event != .teardown {
                    Button("Retry") { center.retry(run) }
                        .buttonStyle(.ds(.secondary, size: .small))
                }
                Button("Dismiss") { center.dismiss(run) }
                    .buttonStyle(.ds(.ghost, size: .small))
            }
            if !run.output.isEmpty {
                Button(showsOutput ? "Less" : "Output") { showsOutput.toggle() }
                    .buttonStyle(.ds(.ghost, size: .small))
            }
        }
    }
}
