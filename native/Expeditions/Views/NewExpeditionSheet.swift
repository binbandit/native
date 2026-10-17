#if EXPEDITIONS_WIP
import NativeAutomation
import NativeExpeditions
import SwiftUI

/// Sets out on an expedition: the objective, the project, the crew, the base and the budget, with
/// what's checked before anything starts. Nothing changes in the project until the user approves
/// the lead's route.
struct NewExpeditionSheet: View {
    /// Called with the new expedition once it's under way.
    let onStart: (Expedition.ID) -> Void

    @Environment(AppModel.self) private var model
    @Environment(ExpeditionCenter.self) private var center
    @Environment(\.dismiss) private var dismiss

    @State private var objective = ""
    @State private var projectID: Project.ID?
    @State private var lead: WorkflowAgent.ID = ""
    @State private var builders: Set<WorkflowAgent.ID> = []
    @State private var reviewer: WorkflowAgent.ID = ""
    @State private var usesWorktree = true
    @State private var maxCost = ""
    @State private var maxMinutes = ""
    @State private var opensPullRequest = true
    @State private var probe: ExpeditionProjectProbe?
    @FocusState private var isObjectiveFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.xl) {
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        Text("New Expedition")
                            .font(.dsTitle3)
                            .foregroundStyle(.dsTextPrimary)
                        Text("The lead reads the project and proposes a route. Nothing changes until you approve it.")
                            .font(.dsBody)
                            .foregroundStyle(.dsTextSecondary)
                    }
                    objectiveField
                    if model.projects.all.count > 1 {
                        field("Project") {
                            Picker("Project", selection: $projectID) {
                                ForEach(model.projects.all) { Text($0.name).tag(Optional($0.id)) }
                            }
                            .labelsHidden()
                        }
                    }
                    crewFields
                    baseAndBudget
                    if !readiness.warnings.isEmpty {
                        VStack(alignment: .leading, spacing: DS.Space.sm) {
                            ForEach(readiness.warnings) { warning in
                                NoticeBanner(tone: warning.isBlocking ? .danger : .warning, title: warning.message)
                            }
                        }
                    }
                }
                .padding(DS.Space.xxl)
            }
            SeparatorLine()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .buttonStyle(.ds(.ghost, size: .medium))
                    .keyboardShortcut(.cancelAction)
                Button("Plan Expedition", action: start)
                    .buttonStyle(.ds(.primary, size: .medium))
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canStart)
                    .help("The lead proposes a route for you to review (⌘Return)")
            }
            .padding(DS.Space.lg)
        }
        .frame(width: 560, height: 640)
        .background(.dsBackground)
        .onAppear(perform: suggestCrew)
        .task(id: project?.url) {
            probe = nil
            if let url = project?.url {
                probe = await center.probe?(url)
            }
        }
    }

    // MARK: - Fields

    private var objectiveField: some View {
        field("Objective") {
            TextEditor(text: $objective)
                .font(.dsCallout)
                .scrollContentBackground(.hidden)
                .focused($isObjectiveFocused)
                .frame(minHeight: 110)
                .padding(DS.Space.sm)
                .background(.dsSurface, in: .rect(cornerRadius: DS.Radius.control))
                .overlay { RoundedRectangle(cornerRadius: DS.Radius.control).strokeBorder(.dsBorder, lineWidth: 1) }
                .overlay(alignment: .topLeading) {
                    if objective.isEmpty {
                        Text("What should the crew get done? Describe the outcome, any constraints, and how you'll judge it.")
                            .font(.dsCallout)
                            .foregroundStyle(.dsTextTertiary)
                            .padding(DS.Space.md)
                            .allowsHitTesting(false)
                    }
                }
                .onAppear { isObjectiveFocused = true }
        }
    }

    private var crewFields: some View {
        field("Crew") {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                if agents.isEmpty {
                    Text("No agent is ready. Install or sign in to one, then come back.")
                        .font(.dsBody)
                        .foregroundStyle(.dsTextSecondary)
                } else {
                    agentPicker("Lead", selection: $lead, help: "Plans the route, revises it between legs and writes the debrief")
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.md) {
                        Text("Builders")
                            .font(.dsBody)
                            .foregroundStyle(.dsTextSecondary)
                            .frame(width: 72, alignment: .leading)
                        VStack(alignment: .leading, spacing: DS.Space.xs) {
                            ForEach(agents) { agent in
                                Toggle(agent.name, isOn: Binding(
                                    get: { builders.contains(agent.id) },
                                    set: { if $0 { builders.insert(agent.id) } else if builders.count > 1 { builders.remove(agent.id) } }
                                ))
                                .font(.dsBody)
                            }
                        }
                    }
                    agentPicker("Reviewer", selection: $reviewer, help: "Checks each leg; a different provider than the builders catches more")
                }
            }
        }
    }

    private var baseAndBudget: some View {
        field("Setup") {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                Toggle("Work in a new worktree, on a branch of its own", isOn: $usesWorktree)
                Toggle("Open a pull request when it's done", isOn: $opensPullRequest)
                HStack(spacing: DS.Space.md) {
                    Text("Budget")
                        .foregroundStyle(.dsTextSecondary)
                        .frame(width: 72, alignment: .leading)
                    TextField("No cost limit", text: $maxCost, prompt: Text("$ cost limit"))
                        .frame(width: 120)
                    TextField("No time limit", text: $maxMinutes, prompt: Text("minutes working"))
                        .frame(width: 140)
                }
                .textFieldStyle(.roundedBorder)
            }
            .font(.dsBody)
        }
    }

    private func agentPicker(_ title: String, selection: Binding<WorkflowAgent.ID>, help: String) -> some View {
        HStack(spacing: DS.Space.md) {
            Text(title)
                .font(.dsBody)
                .foregroundStyle(.dsTextSecondary)
                .frame(width: 72, alignment: .leading)
            Picker(title, selection: selection) {
                ForEach(agents) { Label($0.name, systemImage: $0.symbol).tag($0.id) }
            }
            .labelsHidden()
            .fixedSize()
            .help(help)
        }
    }

    private func field(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text(title)
                .font(.dsCaptionMedium)
                .foregroundStyle(.dsTextTertiary)
            content()
        }
    }

    // MARK: - State

    private var agents: [WorkflowAgent] {
        center.host?.expeditionAgents ?? []
    }

    private var project: Project? {
        projectID.flatMap { id in model.projects.all.first { $0.id == id } } ?? model.currentProject
    }

    private var crew: Crew? {
        guard let lead = agents.first(where: { $0.id == lead }), let reviewer = agents.first(where: { $0.id == reviewer }) else { return nil }
        return Crew(lead: lead, builders: agents.filter { builders.contains($0.id) }, reviewer: reviewer)
    }

    private var budget: ExpeditionBudget {
        ExpeditionBudget(
            maxCost: Double(maxCost.trimmingCharacters(in: CharacterSet(charactersIn: "$ "))).flatMap { $0 > 0 ? $0 : nil },
            maxDuration: Double(maxMinutes.trimmingCharacters(in: .whitespaces)).flatMap { $0 > 0 ? $0 * 60 : nil })
    }

    private var readiness: ExpeditionReadiness {
        var readiness = ExpeditionReadiness()
        readiness.crew = crew
        readiness.unavailableAgents = model.agents.filter { !$0.isReady }.map { runtime in
            "\(runtime.agent.displayName) can't join the crew: \(runtime.status.label.lowercased())." + (runtime.status.guidance.map { " \($0)" } ?? "")
        }
        readiness.isRepository = probe?.isRepository
        readiness.hasUncommittedChanges = probe?.hasUncommittedChanges ?? false
        readiness.usesWorktree = usesWorktree
        readiness.budget = budget
        readiness.opensPullRequest = opensPullRequest
        readiness.gitHubReady = probe?.gitHubReady
        return readiness
    }

    private var canStart: Bool {
        !objective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && project != nil && readiness.canStart
    }

    private func suggestCrew() {
        projectID = model.currentProject?.id
        guard let suggested = Crew.suggested(from: agents, preferring: model.defaultAgent?.id.rawValue) else { return }
        lead = suggested.lead.id
        builders = Set(suggested.builders.map(\.id))
        reviewer = suggested.reviewer.id
    }

    private func start() {
        guard canStart, let project, let crew else { return }
        // Without a repository there's no worktree to make and no pull request to open.
        let isRepository = probe?.isRepository ?? true
        let id = center.runner.start(
            objective: objective, project: project.url, usesWorktree: usesWorktree && isRepository, crew: crew, budget: budget,
            settings: ExpeditionSettings(opensPullRequest: opensPullRequest && isRepository))
        dismiss()
        onStart(id)
    }
}
#endif
