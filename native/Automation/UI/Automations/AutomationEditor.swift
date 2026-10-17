import NativeAutomation
import SwiftUI

/// Makes or edits an automation: when it runs, what it does, and where.
struct AutomationEditor: View {
    struct Project: Hashable, Identifiable {
        let url: URL
        let name: String

        var id: URL { url }
    }

    enum ActionKind: String, CaseIterable, Identifiable {
        case prompt = "Prompt"
        case goal = "Goal"
        case workflow = "Workflow"

        var id: String { rawValue }
    }

    let isNew: Bool
    let projects: [Project]
    let agents: [WorkflowAgent]
    let workflows: [WorkflowDefinition]
    let onSave: (Automation) -> Void
    let onCancel: () -> Void

    private let original: Automation
    @State private var name: String
    @State private var triggers: [AutomationTrigger]
    @State private var kind: ActionKind
    @State private var text: String
    @State private var budget: GoalBudget
    @State private var workflowID: String
    @State private var agent: WorkflowAgent.ID?
    @State private var project: URL?
    @State private var placement: AutomationPlacement

    /// `automation` is the one being edited, or a template's prototype for a new one.
    init(
        automation: Automation, isNew: Bool, projects: [Project], agents: [WorkflowAgent], workflows: [WorkflowDefinition],
        onSave: @escaping (Automation) -> Void, onCancel: @escaping () -> Void
    ) {
        original = automation
        self.isNew = isNew
        self.projects = projects
        self.agents = agents
        self.workflows = workflows
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: automation.name)
        _triggers = State(initialValue: automation.triggers)
        _agent = State(initialValue: automation.agent)
        _project = State(initialValue: projects.contains { $0.url == automation.project } ? automation.project : projects.first?.url)
        _placement = State(initialValue: automation.placement)
        switch automation.action {
        case .prompt(let prompt):
            _kind = State(initialValue: .prompt)
            _text = State(initialValue: prompt)
            _budget = State(initialValue: GoalBudget(maxIterations: 6))
            _workflowID = State(initialValue: workflows.first?.id ?? "")
        case .goal(let objective, let budget):
            _kind = State(initialValue: .goal)
            _text = State(initialValue: objective)
            _budget = State(initialValue: budget)
            _workflowID = State(initialValue: workflows.first?.id ?? "")
        case .workflow(let id, let input):
            _kind = State(initialValue: .workflow)
            _text = State(initialValue: input)
            _budget = State(initialValue: GoalBudget(maxIterations: 6))
            _workflowID = State(initialValue: id)
        }
    }

    private var action: AutomationAction {
        switch kind {
        case .prompt: .prompt(text)
        case .goal: .goal(objective: text, budget: budget)
        case .workflow: .workflow(id: workflowID, input: text)
        }
    }

    private var canSave: Bool {
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return !name.trimmingCharacters(in: .whitespaces).isEmpty && project != nil && (hasText || kind == .workflow)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            Text(isNew ? "New Automation" : "Edit Automation")
                .font(.dsTitle3)
                .foregroundStyle(.dsTextPrimary)
            AutomationTextField(label: "Name", text: $name, placeholder: "Fix failing CI")
            whenSection
            doSection
            whereSection
            footer
        }
        .padding(DS.Space.xxl)
        .frame(width: AutomationMetrics.pickerWidth)
        .background(.dsBackground)
    }

    private var whenSection: some View {
        section("When") {
            ForEach(triggers.indices, id: \.self) { index in
                AutomationTriggerRow(trigger: $triggers[index]) { triggers.remove(at: index) }
            }
            if triggers.isEmpty {
                Text("No triggers: it runs only when you run it.")
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextTertiary)
            }
            Menu {
                Section("Schedule") {
                    Button("Every Day") { triggers.append(.schedule(.daily(hour: 9, minute: 0))) }
                    Button("Every Week") { triggers.append(.schedule(.weekly(weekday: 2, hour: 9, minute: 0))) }
                    Button("Every Few Hours") { triggers.append(.schedule(.everyHours(4))) }
                }
                Section("Event") {
                    ForEach(AutomationEventKind.allCases, id: \.self) { kind in
                        Button(kind.label) { triggers.append(.event(kind)) }
                    }
                }
            } label: {
                Label("Add Trigger", systemImage: "plus")
                    .pillChrome()
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private var doSection: some View {
        section("Do") {
            Picker("Action", selection: $kind) {
                ForEach(ActionKind.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            if kind == .workflow {
                Picker("Workflow", selection: $workflowID) {
                    ForEach(workflows) { Text($0.name).tag($0.id) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
            }
            AutomationTextField(label: kind.rawValue, text: $text, placeholder: placeholder, axis: .vertical, lines: 3...8)
            if kind == .goal {
                GoalBudgetFields(budget: $budget)
            }
            Text("Runs started by an event get its details (the pull request, the task) added to this.")
                .font(.dsCaption)
                .foregroundStyle(.dsTextTertiary)
        }
    }

    private var placeholder: String {
        switch kind {
        case .prompt: "Run the tests and summarize any failures"
        case .goal: "Every test passes on the pull request's branch"
        case .workflow: "What the workflow should do"
        }
    }

    private var whereSection: some View {
        section("Where") {
            HStack(spacing: DS.Space.lg) {
                Picker("Project", selection: $project) {
                    ForEach(projects) { Text($0.name).tag(Optional($0.url)) }
                }
                .pickerStyle(.menu)
                .fixedSize()
                Picker("Agent", selection: $agent) {
                    Text("Default agent").tag(WorkflowAgent.ID?.none)
                    ForEach(agents) { Text($0.name).tag(Optional($0.id)) }
                }
                .pickerStyle(.menu)
                .fixedSize()
                Picker("Work in", selection: $placement) {
                    ForEach(AutomationPlacement.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
                .fixedSize()
            }
            .font(.dsBody)
            Text(placement == .worktree ? "Each run gets a fresh worktree on its own branch, so it never touches your checkout." : "Runs work in the project folder as it is, alongside you.")
                .font(.dsCaption)
                .foregroundStyle(.dsTextTertiary)
        }
    }

    private var footer: some View {
        HStack(spacing: DS.Space.md) {
            Spacer(minLength: 0)
            Button("Cancel", action: onCancel)
                .buttonStyle(.ds(.secondary, size: .medium))
                .keyboardShortcut(.cancelAction)
            Button(isNew ? "Create Automation" : "Save") {
                guard let project else { return }
                var automation = original
                automation.name = name.trimmingCharacters(in: .whitespaces)
                automation.triggers = triggers
                automation.action = action
                automation.agent = agent
                automation.project = project
                automation.placement = placement
                onSave(automation)
            }
            .buttonStyle(.ds(.primary, size: .medium))
            .keyboardShortcut(.defaultAction)
            .disabled(!canSave)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text(title)
                .font(.dsBodyMedium)
                .foregroundStyle(.dsTextSecondary)
            content()
        }
    }
}
