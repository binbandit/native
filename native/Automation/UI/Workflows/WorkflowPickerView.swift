import SwiftUI

/// Starts a workflow against the current project: pick one, say what it should do, check who runs
/// each step (and change it), then run. Shown as a sheet from Session > Run Workflow (⌥⌘R).
struct WorkflowPickerView: View {
    let entries: [WorkflowLibrary.Entry]
    let agents: [WorkflowAgent]
    let projectName: String
    /// The agents each step would get with the user's overrides.
    let plan: (WorkflowDefinition, [String: WorkflowAgent.ID]) -> [String: WorkflowAssignment]
    let onRun: (_ definition: WorkflowDefinition, _ input: String, _ overrides: [String: WorkflowAgent.ID]) -> Void
    let onCancel: () -> Void

    @State private var selectedID: String?
    @State private var input = ""
    @State private var overrides: [String: WorkflowAgent.ID] = [:]
    @FocusState private var isInputFocused: Bool

    init(
        entries: [WorkflowLibrary.Entry], agents: [WorkflowAgent], projectName: String,
        plan: @escaping (WorkflowDefinition, [String: WorkflowAgent.ID]) -> [String: WorkflowAssignment],
        onRun: @escaping (_ definition: WorkflowDefinition, _ input: String, _ overrides: [String: WorkflowAgent.ID]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.entries = entries
        self.agents = agents
        self.projectName = projectName
        self.plan = plan
        self.onRun = onRun
        self.onCancel = onCancel
        _selectedID = State(initialValue: entries.first(where: \.isRunnable)?.id)
    }

    private var selected: WorkflowDefinition? {
        entries.first { $0.id == selectedID && $0.isRunnable }?.definition
    }

    private var canRun: Bool {
        guard let selected, !agents.isEmpty else { return false }
        return !selected.input.isRequired || !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                header
                cards
                if let selected {
                    form(for: selected)
                }
            }
            .padding(DS.Space.xxl)
            SeparatorLine()
            footer
                .padding(.horizontal, DS.Space.xxl)
                .padding(.vertical, DS.Space.lg)
        }
        .frame(width: AutomationMetrics.pickerWidth)
        .background(.dsBackground)
        .onChange(of: selectedID) { overrides = [:] }
        .onAppear { isInputFocused = true }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(spacing: DS.Space.md) {
                Text("Run a Workflow")
                    .font(.dsTitle3)
                    .foregroundStyle(.dsTextPrimary)
                Badge(projectName)
            }
            Text("Each step runs as its own task, on the agent shown, in this project's folder.")
                .font(.dsBody)
                .foregroundStyle(.dsTextSecondary)
        }
        .tracking(DS.Tracking.tight)
    }

    private var cards: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: AutomationMetrics.cardMinWidth), spacing: DS.Space.md, alignment: .top)], spacing: DS.Space.md) {
            ForEach(entries) { entry in
                WorkflowCard(entry: entry, isSelected: entry.id == selectedID) {
                    selectedID = entry.id
                }
            }
        }
    }

    private func form(for definition: WorkflowDefinition) -> some View {
        let assignments = plan(definition, overrides)
        return VStack(alignment: .leading, spacing: DS.Space.lg) {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text(definition.input.label)
                    .font(.dsBodyMedium)
                    .foregroundStyle(.dsTextPrimary)
                TextField(definition.input.label, text: $input, prompt: Text(definition.input.placeholder ?? "").foregroundStyle(.dsTextQuaternary), axis: .vertical)
                    .lineLimit(2...6)
                    .automationField()
                    .focused($isInputFocused)
                    .labelsHidden()
            }
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                SectionHeader("Steps")
                ForEach(Array(definition.steps.enumerated()), id: \.element.id) { index, step in
                    WorkflowStepPlanRow(index: index, step: step, definition: definition, assignment: assignments[step.id], agents: agents) { agent in
                        overrides[step.id] = agent
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: DS.Space.md) {
            if agents.isEmpty {
                Label("No agent is ready to run steps. Start one from the sidebar.", systemImage: "exclamationmark.triangle")
                    .font(.dsCaption)
                    .foregroundStyle(.dsWarning)
            } else if let broken = brokenSummary {
                Label(broken, systemImage: "exclamationmark.triangle")
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextTertiary)
                    .lineLimit(2)
            }
            Spacer(minLength: DS.Space.lg)
            Button("Cancel", action: onCancel)
                .buttonStyle(.ds(.secondary, size: .medium))
                .keyboardShortcut(.cancelAction)
            Button("Run Workflow") {
                guard let selected else { return }
                onRun(selected, input, overrides)
            }
            .buttonStyle(.ds(.primary, size: .medium))
            .keyboardShortcut(.defaultAction)
            .disabled(!canRun)
        }
    }

    /// Plugins' workflows that can't run, so a missing one isn't a mystery.
    private var brokenSummary: String? {
        let broken = entries.filter { !$0.isRunnable }
        guard !broken.isEmpty else { return nil }
        return broken.count == 1 ? "1 workflow can't run; hover it to see why." : "\(broken.count) workflows can't run; hover them to see why."
    }
}
