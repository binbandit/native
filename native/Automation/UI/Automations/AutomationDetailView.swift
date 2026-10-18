import NativeAutomation
import SwiftUI

/// One automation: what it does and when, the controls for it, and its run history.
struct AutomationDetailView: View {
    let automation: Automation
    let runs: [AutomationRun]
    let nextRun: Date?
    let agentName: String?
    let onRunNow: () -> Void
    let onTogglePause: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onOpenRun: (WorkflowRun.ID) -> Void
    let onStopRun: (AutomationRun.ID) -> Void

    @State private var isConfirmingDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xxl) {
                header
                history
            }
            .frame(maxWidth: DS.Size.contentColumn, alignment: .leading)
            .padding(DS.Space.xxl)
            .frame(maxWidth: .infinity)
        }
        .background(.dsBackground)
        .confirmationDialog("Delete \u{201C}\(automation.name)\u{201D}?", isPresented: $isConfirmingDelete) {
            Button("Delete Automation", role: .destructive, action: onDelete)
        } message: {
            Text("Its run history goes with it. Runs in progress are stopped; their sessions stay with their agents.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            HStack(alignment: .top, spacing: DS.Space.md) {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text(automation.name)
                        .font(.dsTitle2)
                        .foregroundStyle(.dsTextPrimary)
                    Text(facts)
                        .font(.dsCaption)
                        .foregroundStyle(.dsTextTertiary)
                }
                .tracking(DS.Tracking.tight)
                Spacer(minLength: DS.Space.lg)
                Button("Run Now", systemImage: "play.fill", action: onRunNow)
                    .buttonStyle(.ds(.primary, size: .medium))
                    .disabled(runs.first?.status.isOpen == true)
                Button(
                    automation.isPaused ? "Resume" : "Pause",
                    systemImage: automation.isPaused ? "play.circle" : "pause.circle", action: onTogglePause
                )
                .buttonStyle(.ds(.secondary, size: .medium))
                Menu {
                    Button("Edit…", systemImage: "pencil", action: onEdit)
                    Button("Delete…", systemImage: "trash", role: .destructive) { isConfirmingDelete = true }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: DS.Size.controlSM, height: DS.Size.controlSM)
                        .contentShape(.rect)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("More")
            }
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                ForEach(Array(automation.triggers.enumerated()), id: \.offset) { _, trigger in
                    Label(trigger.summary, systemImage: trigger.systemImage)
                }
                Label(automation.action.summary + ": " + actionText, systemImage: "text.alignleft")
                    .lineLimit(2)
            }
            .font(.dsBody)
            .foregroundStyle(.dsTextSecondary)
            if let note = scheduleNote {
                Text(note)
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextTertiary)
            }
        }
    }

    private var facts: String {
        [automation.project.lastPathComponent, agentName ?? "Default agent", automation.placement.label].joined(
            separator: " · ")
    }

    private var actionText: String {
        switch automation.action {
        case .prompt(let text), .goal(let text, _): text
        case .workflow(let id, let input): input.isEmpty ? id : "\(id): \(input)"
        }
    }

    private var scheduleNote: String? {
        if automation.isPaused {
            return "Paused. Nothing runs until you resume it; scheduled times that pass meanwhile are skipped."
        }
        if let nextRun {
            return
                "Next run \(DSFormat.timeAndCountdown(nextRun, now: .now)). Runs only while Native is running; a time missed while it's closed runs once when it's back."
        }
        return nil
    }

    @ViewBuilder private var history: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("Runs")
            if runs.isEmpty {
                Text("No runs yet. Run it now to see how it goes.")
                    .font(.dsBody)
                    .foregroundStyle(.dsTextTertiary)
                    .padding(DS.Space.md)
            } else {
                ForEach(runs) { run in
                    AutomationRunRow(run: run, onOpen: run.workflowRun.map { id in { onOpenRun(id) } }) {
                        onStopRun(run.id)
                    }
                    if run.id != runs.last?.id {
                        SeparatorLine()
                    }
                }
            }
        }
    }
}
