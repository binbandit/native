import SwiftUI
import TaskScripts

/// Above a task's conversation: how its worktree's setup is going (running with its output, asking
/// to run the repository's script, done, or failed with Retry and Skip), and any other script of the
/// task's that failed. Other scripts run quietly; their log is in the status bar. Shows nothing for
/// a task without any of these.
struct TaskScriptBanner: View {
    let folder: URL

    @Environment(TaskScriptCenter.self) private var center
    @State private var editing: TaskScriptEditorSheet.Target?

    var body: some View {
        let setup = center.setupRun(in: folder).flatMap { $0.isDismissed || $0.state == .skipped ? nil : $0 }
        let failures = center.failures(in: folder)
        if setup != nil || !failures.isEmpty {
            VStack(spacing: 0) {
                if let setup {
                    TaskScriptSetupStrip(run: setup) { editing = $0 }
                    SeparatorLine()
                }
                ForEach(failures) { run in
                    TaskScriptFailureStrip(run: run) { editing = $0 }
                    SeparatorLine()
                }
            }
            .sheet(item: $editing) { target in
                TaskScriptEditorSheet(target: target)
            }
        }
    }
}

/// A strip of the banner: glyph, text and actions, tinted when something went wrong.
struct TaskScriptStrip<Glyph: View, Content: View>: View {
    var isFailure = false
    var onDismiss: (() -> Void)?
    @ViewBuilder var glyph: Glyph
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.sm) {
            glyph
                .frame(width: TaskScriptMetrics.loader)
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                content
            }
            .tracking(DS.Tracking.tight)
            .frame(maxWidth: .infinity, alignment: .leading)
            if let onDismiss {
                IconButton("Dismiss", systemImage: "xmark", action: onDismiss)
                    .dsHitTarget(DS.Size.controlXS)
            }
        }
        .padding(.leading, DS.Space.lg)
        .padding(.trailing, DS.Space.xs)
        .padding(.vertical, DS.Space.md)
        .background(isFailure ? Color.dsDanger.opacity(0.06) : .clear)
    }
}

/// A strip's title and the sentence under it.
struct TaskScriptStripText: View {
    let title: String
    var message: String?

    var body: some View {
        Text(title)
            .font(.dsBodyMedium)
            .foregroundStyle(.dsTextPrimary)
        // Wrapping comes from the strip's width. `fixedSize` here would size the window's minimum
        // height from the text laid out at no width at all, growing the window until AppKit gives up.
        if let message {
            HooksProbe {
                Text(message)
                    .font(.dsBody)
                    .foregroundStyle(.dsTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The failure of a script other than setup: which one, how, its last lines, Retry and Dismiss.
private struct TaskScriptFailureStrip: View {
    let run: TaskScriptRun
    let edit: (TaskScriptEditorSheet.Target) -> Void

    @Environment(TaskScriptCenter.self) private var center

    var body: some View {
        if let failure = run.failure {
            TaskScriptStrip(isFailure: true, onDismiss: { center.dismiss(run) }) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.dsDanger)
            } content: {
                TaskScriptStripText(
                    title: "\(failure.script.name) \(failure.result.outcome.phrase)",
                    message: TaskScriptFailureText.detail(failure, ofRun: run))
                TaskScriptOutputView(output: run.output, lines: TaskScriptMetrics.failureLines)
                HStack(spacing: DS.Space.sm) {
                    Button("Retry") { center.retry(run) }
                        .buttonStyle(.ds(.secondary))
                    Button(failure.script.source == .repository ? "Show Script" : "Edit Script…") {
                        edit(.init(event: run.event, scope: .init(failure.script.source, project: run.projectRoot)))
                    }
                    .buttonStyle(.ds(.ghost))
                }
                .padding(.top, DS.Space.xxs)
            }
        }
    }
}

/// Words for a failed script, shared by the banner and the log.
enum TaskScriptFailureText {
    /// What happened beyond the title, and what the user can do.
    static func detail(_ failure: TaskScriptReport, ofRun run: TaskScriptRun) -> String {
        var parts: [String] = []
        if case .couldNotStart(let reason) = failure.result.outcome {
            parts.append(reason)
        }
        switch run.event {
        case .setup:
            parts.append("Your messages wait until setup works or you skip it.")
        case .teardown:
            parts.append("The worktree was removed anyway.")
        case .taskStarted, .turnFinished, .taskDeleted:
            parts.append("Nothing else was affected. Fix the script, then retry.")
        }
        return parts.joined(separator: " ")
    }
}

// HOOKS-EXPERIMENT: logs the proposals the banner text gets.
struct HooksProbe: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let size = subviews.first?.sizeThatFits(proposal) ?? .zero
        NSLog("HOOKSPROBE proposal w=%@ h=%@ -> %.0fx%.0f", proposal.width.map { "\($0)" } ?? "nil", proposal.height.map { "\($0)" } ?? "nil", size.width, size.height)
        return size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}
