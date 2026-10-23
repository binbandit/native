import SwiftUI
import Terminal

/// Output from a background command in the task's terminal. The runner owns cancellation and
/// retry, so the same policy and timeout apply whether they are requested here or elsewhere.
struct TerminalLogView: View {
    let log: TerminalLog

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ScrollView([.horizontal, .vertical]) {
                    Text(
                        verbatim: log.output.isEmpty
                            ? (log.job.isRunning ? "Starting the command…" : "The command produced no output.")
                            : log.output
                    )
                    .codeTextStyle()
                    .foregroundStyle(.dsTextPrimary)
                    .textSelection(.enabled)
                    .padding(DS.Space.md)
                    .frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .topLeading)
                    .accessibilityIdentifier("worktreeCommandOutput")
                }
                .defaultScrollAnchor(.bottomLeading)
            }
            if let outcome = log.job.outcome {
                NoticeBanner(
                    tone: outcome.succeeded ? .success : failed ? .danger : .info,
                    title: outcome.summary(of: log.job.name), detail: log.detail
                ) {
                    Button(outcome.succeeded ? "Run Again" : "Retry", action: log.retry)
                        .buttonStyle(.ds(.secondary))
                }
                .padding(DS.Space.md)
            }
        }
        .background(.dsSurfaceSunken)
    }

    private var failed: Bool {
        if case .exited(status: let status?, _) = log.job.outcome { status != 0 } else { false }
    }
}

#if DEBUG
#Preview("Worktree commands - Running and failed") {
    DSPreviewPair {
        VStack {
            TerminalLogView(log: TerminalLogPreviewFixtures.running)
            TerminalLogView(log: TerminalLogPreviewFixtures.failed)
        }
        .frame(width: 640, height: 400)
    }
}

#endif
