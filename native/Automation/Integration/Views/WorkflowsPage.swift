import SwiftUI

/// The Workflows page: runs, newest first, and the library to start one from. A run opens on its
/// own page, with the way back in the toolbar.
struct WorkflowsPage<Transcript: View>: View {
    @Binding var path: [WorkflowRun.ID]
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
                }
                .frame(maxWidth: AutomationMetrics.columnWidth, alignment: .leading)
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
                Text("Sequences of agent tasks across providers, such as plan with one agent, implement with another and review with the first. Each step runs as its own task.")
                    .font(.dsBody)
                    .foregroundStyle(.dsTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .tracking(DS.Tracking.tight)
            Spacer(minLength: DS.Space.lg)
            Button("Run Workflow…", systemImage: "play.fill") { center.requestPicker() }
                .buttonStyle(.ds(.primary, size: .medium))
                .help("Run a workflow in the current project (⌥⌘R)")
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
            LazyVGrid(columns: [GridItem(.adaptive(minimum: AutomationMetrics.cardMinWidth), spacing: DS.Space.md, alignment: .top)], spacing: DS.Space.md) {
                ForEach(center.library.entries) { entry in
                    WorkflowCard(entry: entry, isSelected: false) { center.requestPicker(selecting: entry.id) }
                }
            }
        }
    }
}
