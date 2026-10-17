import SwiftUI

/// Warns, early, that a session's context is nearly full, with the breakdown a click away and
/// compacting as the next step. Shows nothing until the window passes 90%.
struct ContextPressureBanner<Source: ContextSource>: View {
    let source: Source
    var chrome: UsageBannerChrome = .card

    @State private var dismissedAt: Double?
    @State private var isShowingBreakdown = false

    var body: some View {
        if let fraction = source.fractionUsed, ContextPressure(fraction: fraction) == .critical,
            dismissedAt.map({ fraction > $0 + 0.02 }) ?? true
        {
            UsageBannerRow(
                systemImage: "exclamationmark.circle",
                tint: .dsWarning,
                title: "Context \(DSFormat.percent(fraction)) full",
                detail: "\(source.agentName) compacts the conversation on its own when the window runs out.",
                chrome: chrome
            ) {
                Button("Breakdown") { isShowingBreakdown = true }
                    .buttonStyle(.ds(.ghost))
                    .popover(isPresented: $isShowingBreakdown, arrowEdge: .top) {
                        ContextBreakdownView(source: source)
                    }
                if source.canCompact {
                    Button("Compact Now") {
                        Task { await source.compact() }
                    }
                    .buttonStyle(.ds(.secondary))
                    .help("Summarizes the conversation so far to free up room, as /compact does")
                }
                // Dismissed until it fills noticeably further.
                IconButton("Dismiss", systemImage: "xmark") { dismissedAt = fraction }
            }
        }
    }
}
