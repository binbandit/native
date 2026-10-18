import NativeAutomation
import SwiftUI

/// An automation in the list, as a table row: its state, name, triggers, when it
/// runs next and how it last went, with Run Now always in reach (and everything else in the context
/// menu, which is also the touch equivalent).
struct AutomationRow: View {
    let automation: Automation
    let latest: AutomationRun?
    let nextRun: Date?
    let onOpen: () -> Void
    let onRunNow: () -> Void
    let onTogglePause: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        // Run Now sits beside the row's open button, not inside it, so pointer, keyboard and
        // VoiceOver all reach it on its own.
        HStack(alignment: .center, spacing: DS.Space.sm) {
            Button(action: onOpen) {
                HStack(alignment: .top, spacing: DS.Space.md) {
                    AutomationStatusGlyph(glyph: automation.glyph(latest: latest))
                        .padding(.top, DS.Space.xxs)
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text(automation.name)
                            .font(.dsCalloutMedium)
                            .foregroundStyle(automation.isPaused ? .dsTextSecondary : .dsTextPrimary)
                        Text("\(automation.triggerSummary) · \(automation.project.lastPathComponent)")
                            .font(.dsCaption)
                            .foregroundStyle(.dsTextTertiary)
                            .lineLimit(1)
                    }
                    .tracking(DS.Tracking.tight)
                    Spacer(minLength: DS.Space.md)
                    VStack(alignment: .trailing, spacing: DS.Space.xxs) {
                        Text(schedule)
                            .font(.dsCaption)
                            .foregroundStyle(.dsTextSecondary)
                        if let latest {
                            Text(latest.status.label)
                                .font(.dsCaption)
                                .foregroundStyle(AutomationGlyph(run: latest.status).tint)
                        }
                    }
                }
                .padding(.vertical, DS.Space.md)
                .padding(.leading, DS.Space.md)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            IconButton("Run Now", systemImage: "play.fill", action: onRunNow)
                .disabled(latest?.status.isOpen == true)
                .padding(.trailing, DS.Space.md)
        }
        .contextMenu {
            Button("Run Now", systemImage: "play.fill", action: onRunNow)
            Button(automation.isPaused ? "Resume" : "Pause", systemImage: automation.isPaused ? "play.circle" : "pause.circle", action: onTogglePause)
            Button("Edit…", systemImage: "pencil", action: onEdit)
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }

    private var schedule: String {
        if automation.isPaused { return "Paused" }
        guard let nextRun else { return automation.triggers.isEmpty ? "Manual" : "On events" }
        return "Next " + DSFormat.time(nextRun, now: .now)
    }
}
