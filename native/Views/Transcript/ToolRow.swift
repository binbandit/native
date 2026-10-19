import ACP
import SwiftUI

/// When a live call started and finished, and how its command exited; all nil for replayed history.
struct ToolRowTiming: Equatable {
    var startedAt: Date?
    var finishedAt: Date?
    var exitCode: Int?

    init(_ call: ToolCallState) {
        startedAt = call.startedAt
        finishedAt = call.finishedAt
        exitCode = call.exitCode
    }
}

/// A tool call's one line: glyph, verb and subject, a chevron on hover, then its status at the
/// trailing edge. The leading part is one button that opens the details (Space with keyboard focus,
/// a tap, or the accessibility press).
struct ToolRow<Accessory: View>: View {
    let presentation: ToolPresentation
    let phase: ToolPhase
    let timing: ToolRowTiming
    let isExpandable: Bool
    let isExpanded: Bool
    let toggle: () -> Void
    @ViewBuilder let accessory: Accessory

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            Button(action: toggle) {
                HStack(spacing: DS.Space.sm) {
                    icon
                    title
                    if isExpandable {
                        DisclosureChevron(isExpanded: isExpanded)
                            .opacity(isHovering || isExpanded || DS.isTouchPlatform ? 1 : 0)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .allowsHitTesting(isExpandable)
            .accessibilityElement(children: .combine)
            .accessibilityValue(accessibilityValue)
            .accessibilityHint(isExpandable ? (isExpanded ? "Hides the output" : "Shows the output") : "")

            accessory
            ToolRowStatus(presentation: presentation, phase: phase, timing: timing)
        }
        .padding(.vertical, DS.Space.xs)
        .trackHover($isHovering)
    }

    private var icon: some View {
        Group {
            if presentation.showsStatusIcon {
                // Subagent rows: their status, not the tool, is what matters at a glance.
                Image(systemName: statusSymbol)
                    .symbolEffect(
                        .variableColor.iterative.dimInactiveLayers.nonReversing, options: .repeat(.continuous),
                        isActive: phase == .running
                    )
                    .foregroundStyle(phase == .failed ? Color.dsDanger : .dsTextSecondary)
                    .contentTransition(.symbolEffect(.replace))
            } else {
                Image(systemName: presentation.glyph.systemImage)
                    .foregroundStyle(.dsTextSecondary)
            }
        }
        .symbolRenderingMode(.hierarchical)
        .font(.dsBody)
        .frame(width: DS.Size.rowLeading)
    }

    private var statusSymbol: String {
        switch phase {
        case .running, .awaitingApproval: "progress.indicator"
        case .completed: "checkmark.circle"
        case .failed: "xmark.circle"
        case .cancelled: "stop.circle"
        }
    }

    private var title: some View {
        HStack(spacing: DS.Space.sm) {
            if let verb = presentation.verb {
                Text(verb)
                    .foregroundStyle(isHovering && isExpandable ? Color.dsTextPrimary : .dsTextSecondary)
                    .shimmering(phase == .running)
                    .layoutPriority(1)
            }
            subject
            if let subtitle = presentation.subtitle {
                Text(subtitle)
                    .foregroundStyle(.dsTextTertiary)
            }
        }
        .lineLimit(1)
    }

    @ViewBuilder private var subject: some View {
        // Subagent rows already animate their status icon.
        let text = Text(presentation.subject)
            .truncationMode(.middle)
            .shimmering(phase == .running && !presentation.showsStatusIcon)
        switch presentation.subjectStyle {
        case .plain:
            text.foregroundStyle(subjectStyle)
        case .command:
            text
                .font(.dsMono)
                .foregroundStyle(subjectStyle)
        case .emphasized:
            text.foregroundStyle(.dsTextPrimary)
        case .chip:
            HStack(spacing: DS.Space.sm) {
                text.foregroundStyle(isHovering && isExpandable ? Color.dsTextPrimary : .dsTextSecondary)
                if let stats = presentation.stats {
                    Rectangle()
                        .fill(.dsSeparator)
                        .frame(width: 1, height: 11)
                    DiffStatsText(stats: stats)
                }
            }
            .font(.dsBody)
            .padding(.horizontal, DS.Space.md)
            .padding(.vertical, DS.Space.xxs)
            .background(.dsSurfaceSunken, in: .rect(cornerRadius: DS.Radius.row, style: .continuous))
        }
    }

    /// A subject reads tertiary after a verb and secondary on its own; hover lifts it to primary.
    private var subjectStyle: Color {
        if isHovering, isExpandable {
            .dsTextPrimary
        } else if presentation.verb == nil {
            .dsTextSecondary
        } else {
            .dsTextTertiary
        }
    }

    private var accessibilityValue: String {
        let status =
            switch phase {
            case .running: "Running"
            case .awaitingApproval: "Waiting for approval"
            case .completed: "Completed"
            case .failed: presentation.failureText(exitCode: timing.exitCode)
            case .cancelled: "Interrupted"
            }
        guard isExpandable else { return status }
        return "\(status), \(isExpanded ? "expanded" : "collapsed")"
    }
}

/// The trailing edge of a tool row: a clock while it runs, how long it took once it's done, and a
/// word when something needs attention.
private struct ToolRowStatus: View {
    let presentation: ToolPresentation
    let phase: ToolPhase
    let timing: ToolRowTiming

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            switch phase {
            case .running:
                if let startedAt = timing.startedAt {
                    ToolRunningClock(since: startedAt)
                }
            case .awaitingApproval:
                Text("Approval required")
                    .foregroundStyle(.dsAccentText)
            case .failed where !presentation.showsStatusIcon:
                Text(presentation.failureText(exitCode: timing.exitCode))
                    .foregroundStyle(.dsDanger)
                duration
            case .cancelled:
                Text("Interrupted")
                    .foregroundStyle(.dsTextTertiary)
            case .completed, .failed:
                duration
            }
        }
        .font(.dsCaption)
        .lineLimit(1)
        .fixedSize()
    }

    /// How long a finished live call took, from a second up: under that it's noise.
    @ViewBuilder private var duration: some View {
        if let start = timing.startedAt, let end = timing.finishedAt, end.timeIntervalSince(start) >= 1 {
            ElapsedTimeText(since: start, until: end)
                .foregroundStyle(.dsTextTertiary)
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
