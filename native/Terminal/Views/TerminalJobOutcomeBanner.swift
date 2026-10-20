import SwiftUI
import Terminal

/// How a job tab's run ended, under its output: finished, failed with its exit code, or stopped,
/// how long it took, and Run Again in the same tab. The command itself heads the output.
struct TerminalJobOutcomeBanner: View {
    let job: TerminalJob
    let outcome: TerminalJob.Outcome
    let runAgain: () -> Void

    var body: some View {
        NoticeBanner(
            // Success, failure with a status, or neither (stopped, or no status reported).
            tone: outcome.succeeded ? .success : failed ? .danger : .info,
            systemImage: symbol,
            title: outcome.summary(of: job.name),
            footnote: "Press any key to close this tab."
        ) {
            Button("Run Again", action: runAgain)
                .buttonStyle(.ds(.secondary))
        }
    }

    private var failed: Bool {
        if case .exited(status: let status?, _) = outcome { status != 0 } else { false }
    }

    private var symbol: String? {
        if case .stopped = outcome { "stop.circle" } else { nil }
    }
}

extension TerminalJob.Outcome {
    /// What happened, in a line: "Test finished in 12s", "Test failed with exit code 1 after 3s".
    func summary(of name: String) -> String {
        let seconds = duration / .seconds(1)
        let elapsed = seconds < 1 ? "less than a second" : DSFormat.duration(seconds)
        return switch self {
        case .exited(status: 0, _): "\(name) finished in \(elapsed)"
        case .exited(status: let status?, _): "\(name) failed with exit code \(status) after \(elapsed)"
        case .exited(status: nil, _): "\(name) ended after \(elapsed)"
        case .stopped: "\(name) was stopped after \(elapsed)"
        }
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Job outcomes") {
    DSPreviewPair {
        VStack(spacing: DS.Space.md) {
            ForEach(TerminalPreviewFixtures.outcomes, id: \.self) { outcome in
                TerminalJobOutcomeBanner(job: TerminalPreviewFixtures.runningJob, outcome: outcome, runAgain: {})
            }
        }
        .frame(width: 560)
    }
}
#endif
