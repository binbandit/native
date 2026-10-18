import NativeAutomation
import NativeExpeditions
import SwiftUI

/// The top of an expedition: what it's for, where it stands, what it has spent, and pause, wrap up
/// and stop for the whole crew. The bar has one segment per assignment, colored by its status.
struct ExpeditionHeader: View {
    let expedition: Expedition
    let send: (ExpeditionEvent) -> Void

    var body: some View {
        // Ages and working time only move by the minute here; seats tick on their own rows.
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            content(now: timeline.date)
        }
    }

    private func content(now: Date) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            HStack(alignment: .top, spacing: DS.Space.md) {
                Image(systemName: ExpeditionsMetrics.symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(.dsTextSecondary)
                    .frame(width: DS.Size.controlSM, height: DS.Size.controlSM)
                    .background(.dsSurfaceRaised, in: .circle)
                    .overlay { Circle().strokeBorder(.dsSeparator, lineWidth: 1) }
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(expedition.title)
                        .font(.dsTitle3)
                        .foregroundStyle(.dsTextPrimary)
                        .lineLimit(2)
                    Text(expedition.metaLine(now: now))
                        .font(.dsCaption)
                        .monospacedDigit()
                        .foregroundStyle(.dsTextTertiary)
                }
                .tracking(DS.Tracking.tight)
                Spacer(minLength: DS.Space.lg)
                controls
            }
            HStack(spacing: DS.Space.md) {
                StatusIndicator(status: expedition.phase.taskStatus)
                Badge(expedition.phase.label, tone: expedition.phase.tone, style: .mono)
                if !expedition.assignments.isEmpty {
                    HStack(spacing: DS.Space.xxs) {
                        ForEach(expedition.assignments) { run in
                            Rectangle()
                                .fill(run.status.segmentColor)
                                .frame(height: DS.Space.xs)
                                .clipShape(.rect(cornerRadius: DS.Radius.small))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
                } else {
                    Spacer()
                }
                Text(expedition.progressText)
                    .font(.dsCaption)
                    .monospacedDigit()
                    .foregroundStyle(.dsTextTertiary)
                    .fixedSize()
            }
            if let note = phaseNote(now: now) {
                Text(note)
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var controls: some View {
        HStack(spacing: DS.Space.sm) {
            switch expedition.phase {
            case .underway, .needsYou, .limited:
                Button("Pause", systemImage: "pause.fill") { send(.pause) }
                    .buttonStyle(.ds(.secondary))
                    .help("Let running turns finish, then hold the crew")
                moreMenu
            case .paused:
                Button("Resume", systemImage: "play.fill") { send(.resume) }
                    .buttonStyle(.ds(.primary))
                moreMenu
            case .planning, .reviewing, .debriefing:
                Button("Stop", systemImage: "stop.fill") { send(.stop) }
                    .buttonStyle(.ds(.ghost))
                    .help("Stop the expedition and every turn in it")
            case .complete, .stopped:
                EmptyView()
            }
        }
    }

    private var moreMenu: some View {
        Menu {
            Button("Wrap Up", systemImage: "flag.checkered") { send(.wrapUp) }
                .help("Skip what hasn't started and go straight to the debrief")
            Divider()
            Button("Stop Expedition", systemImage: "stop.fill", role: .destructive) { send(.stop) }
        } label: {
            Label("More", systemImage: "ellipsis")
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.ds(.ghost, iconOnly: true))
        .fixedSize()
        .help("More")
    }

    /// Why the expedition isn't moving, when it isn't, and how it ended.
    private func phaseNote(now: Date) -> String? {
        switch expedition.phase {
        case .paused:
            let finishing = expedition.assignments.count { $0.status.isActive }
            return finishing > 0
                ? "Paused. The running turn finishes; nothing new starts until you resume."
                : "Paused. Nothing new starts until you resume."
        case .stopped:
            return "Stopped. Sessions, reports and the worktree stay; nothing more runs."
        case .complete:
            return expedition.endedAt.map {
                "Finished in \(DSFormat.duration($0.timeIntervalSince(expedition.createdAt))), \(DSFormat.duration(expedition.activeTime(at: now))) of it working."
            }
        case .limited:
            return "A provider limit stopped the crew. Work picks back up at the reset on its own."
        case .planning, .reviewing, .underway, .needsYou, .debriefing:
            return nil
        }
    }
}
