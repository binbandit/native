import ACP
import SwiftUI

/// The one line all tool work shows as: a single call, a group of calls, an earlier turn's folded
/// work. A glyph, one plain sentence in one tone, the lines an edit changed, a chevron when it
/// opens, and at the trailing edge how it stands. The leading part is one button that opens the
/// details (Space with keyboard focus, a tap, or the accessibility press).
struct ToolLine<Trailing: View>: View {
    let glyph: DSToolGlyph
    let sentence: String
    var stats: DiffStats?
    /// A sweep across the sentence while the work runs.
    var isBusy = false
    let isExpandable: Bool
    let isExpanded: Bool
    /// The longer form, on hover: the whole path or command, or the agent's own description.
    var help: String?
    /// What the line's state is, for accessibility: "Running", "Exit 1".
    var accessibilityStatus: String?
    let toggle: () -> Void
    @ViewBuilder let trailing: Trailing

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            Button(action: toggle) {
                HStack(spacing: DS.Space.sm) {
                    Image(systemName: glyph.systemImage)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.dsTextTertiary)
                        .frame(width: DS.Size.rowLeading)
                        .accessibilityHidden(true)
                    Text(verbatim: sentence)
                        .foregroundStyle(isHovering && isExpandable ? Color.dsTextPrimary : .dsTextSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .shimmering(isBusy)
                        .contentTransition(.opacity)
                        .animation(.dsStandard, value: sentence)
                    if let stats, stats != DiffStats() {
                        DiffStatsText(stats: stats)
                            .font(.dsCaption)
                            .fixedSize()
                    }
                    if isExpandable {
                        DisclosureChevron(isExpanded: isExpanded)
                            .opacity(isHovering || isExpanded || DS.isTouchPlatform ? 1 : 0)
                            .accessibilityHidden(true)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .allowsHitTesting(isExpandable)
            .accessibilityElement(children: .combine)
            .accessibilityValue(accessibilityValue)
            .accessibilityHint(isExpandable ? (isExpanded ? "Hides the details" : "Shows the details") : "")
            .help(help ?? "")

            trailing
                .font(.dsCaption)
                .lineLimit(1)
                .fixedSize()
        }
        .font(.dsBody)
        .padding(.vertical, DS.Space.xs)
        .trackHover($isHovering)
    }

    private var accessibilityValue: String {
        let state = isExpandable ? (isExpanded ? "expanded" : "collapsed") : nil
        return [accessibilityStatus, state].compactMap(\.self).joined(separator: ", ")
    }
}

extension EnvironmentValues {
    /// The task's folder, so tool rows name the folders they search from there.
    @Entry var toolWorkspaceRoot: String?
}

/// The trailing edge of a tool line: a clock while the work runs long enough to wonder, how long
/// it took once it took long enough to matter, and a word when it didn't simply succeed.
struct ToolLineStatus: View {
    let phase: ToolPhase
    /// "Exit 1", "Rejected": `ToolPhase.outcome`.
    let outcome: String?
    var startedAt: Date?
    var finishedAt: Date?

    /// Shorter than this a finished call's time is noise; longer, it says where the turn's time went.
    static let notableDuration: TimeInterval = 10

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            if phase == .running, let startedAt {
                ToolRunningClock(since: startedAt)
            }
            if let outcome {
                Text(outcome)
                    .foregroundStyle(color)
            }
            if phase != .running, let startedAt, let finishedAt,
                finishedAt.timeIntervalSince(startedAt) >= Self.notableDuration
            {
                ElapsedTimeText(since: startedAt, until: finishedAt)
                    .foregroundStyle(.dsTextTertiary)
            }
        }
    }

    private var color: Color {
        switch phase {
        case .failed: .dsDanger
        case .awaitingApproval: .dsAccentText
        // As quiet as the turn's own "Stopped": nothing went wrong that needs attention.
        case .cancelled, .rejected, .interrupted, .unreported, .running, .completed: .dsTextTertiary
        }
    }
}

/// A running call's elapsed time, from its third second on: sooner it's noise, later it's the
/// cheapest proof the tool isn't stuck. Ticks with the shared `DSSecondClock`.
private struct ToolRunningClock: View {
    let start: Date

    init(since start: Date) {
        self.start = start
    }

    var body: some View {
        let clock = DSSecondClock.shared
        ZStack(alignment: .trailing) {
            // Holds the clock while the label waits for its third second.
            Color.clear.frame(width: 0, height: 0)
            if clock.now.timeIntervalSince(start) >= 3 {
                ElapsedTimeText(since: start)
                    .foregroundStyle(.dsTextTertiary)
                    .transition(.opacity)
            }
        }
        .task { await clock.hold() }
    }
}
