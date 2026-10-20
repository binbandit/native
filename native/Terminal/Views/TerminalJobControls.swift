import SwiftUI
import Terminal

/// The tab bar's trailing edge while the selected tab's job runs: how long it has been running, and
/// Stop. Stopping interrupts it (⌃C); a job that ignores that is ended by stopping again.
struct TerminalJobControls: View {
    let job: TerminalJob
    let stop: () -> Void

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            ElapsedTimeText(since: job.startedAt)
                .font(.dsMonoCaption)
                .foregroundStyle(.dsTextTertiary)
                .accessibilityLabel("Running")
            Button(job.isStopping ? "End Now" : "Stop", systemImage: "stop.fill", action: stop)
                .buttonStyle(.ds(.ghost))
                .help(job.isStopping ? "End \(job.name) now" : "Stop \(job.name) (sends ⌃C)")
        }
    }
}

/// A job tab's status: a loader while it runs, then green, red or gray for how it ended.
struct TerminalJobStatusDot: View {
    let job: TerminalJob

    var body: some View {
        switch job.outcome {
        case nil:
            DotGridLoader(pattern: .waiting)
                .frame(width: DS.Size.statusGlyph, height: DS.Size.statusGlyph)
                .foregroundStyle(.dsTextSecondary)
        case let outcome? where outcome.succeeded:
            StatusDot(color: .dsSuccess)
        case .exited(status: .some, _):
            StatusDot(color: .dsDanger)
        case .exited(status: nil, _), .stopped:
            StatusDot(color: .dsTextTertiary)
        }
    }

    /// "Test, running", "Test, failed".
    static func accessibilityLabel(_ label: String, job: TerminalJob) -> String {
        switch job.outcome {
        case nil: "\(label), running"
        case let outcome? where outcome.succeeded: "\(label), finished"
        case .exited(status: .some, _): "\(label), failed"
        case .exited(status: nil, _): "\(label), ended"
        case .stopped: "\(label), stopped"
        }
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Job controls") {
    DSPreviewPair {
        VStack(alignment: .trailing, spacing: DS.Space.lg) {
            TerminalJobControls(job: TerminalPreviewFixtures.runningJob, stop: {})
            // Stopping again ends a job that ignored ⌃C.
            TerminalJobControls(job: TerminalPreviewFixtures.stoppingJob, stop: {})
            HStack(spacing: DS.Space.md) {
                TerminalJobStatusDot(job: TerminalPreviewFixtures.runningJob)
                ForEach(TerminalPreviewFixtures.outcomes, id: \.self) { outcome in
                    TerminalJobStatusDot(job: TerminalPreviewFixtures.job(ended: outcome))
                }
            }
        }
    }
}
#endif
