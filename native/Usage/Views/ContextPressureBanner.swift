import SwiftUI

/// Warns, early, that a session's context is nearly full, with the breakdown a click away and
/// compacting as the next step. Shows nothing until the window passes 90%, or after the user
/// dismissed it until it fills noticeably further (`dismissedAt`, the share it was dismissed at).
struct ContextPressureBanner<Source: ContextSource>: View {
    let source: Source
    var chrome: UsageBannerChrome = .card
    var dismissedAt: Double?
    var onDismiss: (Double) -> Void = { _ in }

    @State private var isShowingBreakdown = false

    static func shows(fraction: Double?, dismissedAt: Double?) -> Bool {
        guard let fraction, ContextPressure(fraction: fraction) == .critical else { return false }
        return dismissedAt.map { fraction > $0 + 0.02 } ?? true
    }

    var body: some View {
        if let fraction = source.fractionUsed, Self.shows(fraction: fraction, dismissedAt: dismissedAt) {
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
                            .dsPopoverBackground()
                    }
                if source.canCompact {
                    Button("Compact Now") {
                        Task { await source.compact() }
                    }
                    .buttonStyle(.ds(.secondary))
                    .help("Summarizes the conversation so far to free up room, as /compact does")
                }
                // Dismissed until it fills noticeably further.
                IconButton("Dismiss", systemImage: "xmark") { onDismiss(fraction) }
            }
        }
    }
}
