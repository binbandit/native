import NativeAutomation
import SwiftUI

/// The Workflows page: runs, newest first, and the library to start one from. A run opens on its
/// own page, with the way back in the toolbar.
struct WorkflowsPage<Transcript: View>: View {
    @Binding var path: [WorkflowRun.ID]
    /// Opens Automations, turning it on first; nil once it's in the sidebar anyway.
    var onSetUpAutomations: (() -> Void)?
    @ViewBuilder let transcript: (SessionModel) -> Transcript

    @Environment(AutomationCenter.self) private var center

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.xxl) {
                    header
                    if !center.workflows.runs.isEmpty {
                        runs
                    }
                    library
                    if let onSetUpAutomations {
                        automationsTeaser(onSetUpAutomations)
                    }
                }
                .frame(maxWidth: DS.Size.contentColumn, alignment: .leading)
                .padding(DS.Space.xxl)
                .frame(maxWidth: .infinity)
            }
            .background(.dsBackground)
            .navigationTitle("Workflows")
            .navigationDestination(for: WorkflowRun.ID.self) { id in
                WorkflowRunScreen(runID: id, transcript: transcript)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: DS.Space.lg) {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text("Workflows")
                    .font(.dsTitle2)
                    .foregroundStyle(.dsTextPrimary)
                Text(
                    "Sequences of agent tasks across providers, such as plan with one agent, implement with another and review with the first. Each step runs as its own task."
                )
                .font(.dsBody)
                .foregroundStyle(.dsTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .tracking(DS.Tracking.tight)
            Spacer(minLength: DS.Space.lg)
            Button("Run Workflow…", systemImage: "play.fill") { center.requestPicker() }
                .buttonStyle(.ds(.primary, size: .medium))
                .help(CommandRegistry.shared.help("Run a workflow in the current project", for: .workflowRun))
        }
    }

    private var runs: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("Runs")
            ForEach(center.workflows.runs) { run in
                WorkflowRunRow(run: run) { path = [run.id] }
                    .contextMenu {
                        Button("Open") { path = [run.id] }
                        if [.succeeded, .cancelled, .halted].contains(run.phase) {
                            Button("Remove from List", role: .destructive) { center.workflows.remove(run.id) }
                        }
                    }
            }
        }
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            SectionHeader("Library")
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: AutomationMetrics.cardMinWidth), spacing: DS.Space.md, alignment: .top)
                ], spacing: DS.Space.md
            ) {
                ForEach(center.library.entries) { entry in
                    WorkflowCard(entry: entry, isSelected: false) { center.requestPicker(selecting: entry.id) }
                }
            }
        }
    }

    private func automationsTeaser(_ setUp: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: DS.Space.lg) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 14))
                .foregroundStyle(.dsTextSecondary)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text("Run workflows on their own")
                    .font(.dsBodyMedium)
                    .foregroundStyle(.dsTextPrimary)
                Text(
                    "Automations start a prompt, goal or workflow on a schedule, or when a pull request changes or CI fails."
                )
                .font(.dsCaption)
                .foregroundStyle(.dsTextSecondary)
            }
            Spacer(minLength: DS.Space.lg)
            Button("Set Up Automations", action: setUp)
                .buttonStyle(.ds(.secondary, size: .medium))
        }
        .padding(DS.Space.lg)
        .background(.dsSurface, in: .rect(cornerRadius: DS.Radius.card))
        .overlay { RoundedRectangle(cornerRadius: DS.Radius.card).strokeBorder(.dsSeparator, lineWidth: 1) }
    }
}
