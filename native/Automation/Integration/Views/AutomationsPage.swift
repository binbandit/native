import NativeAutomation
import SwiftUI

/// The Automations page: every automation, where it can be run, paused or stopped, and templates
/// to start from. An automation opens on its own page with its run history.
struct AutomationsPage: View {
    /// Shows a run on the Workflows page.
    let onOpenRun: (WorkflowRun.ID) -> Void

    @Environment(AutomationCenter.self) private var center
    @Environment(AppModel.self) private var model
    @State private var path: [Automation.ID] = []
    @State private var editing: Edit?

    private struct Edit: Identifiable {
        let automation: Automation
        let isNew: Bool

        var id: Automation.ID { automation.id }
    }

    private var engine: AutomationEngine {
        center.automations
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.xxl) {
                    header
                    if engine.needsPolling, let problem = engine.eventSourceProblem {
                        NoticeBanner(tone: .warning, systemImage: "exclamationmark.triangle", title: "Pull request events can't fire", detail: problem)
                    }
                    if !engine.automations.isEmpty {
                        list
                    }
                    templates
                }
                .frame(maxWidth: DS.Size.contentColumn, alignment: .leading)
                .padding(DS.Space.xxl)
                .frame(maxWidth: .infinity)
            }
            .background(.dsBackground)
            .navigationTitle("Automations")
            .navigationDestination(for: Automation.ID.self) { id in
                detail(id)
            }
        }
        .sheet(item: $editing) { edit in
            AutomationEditor(
                automation: edit.automation, isNew: edit.isNew,
                projects: model.projects.all.map { AutomationEditor.Project(url: $0.url, name: $0.name) },
                agents: center.host?.workflowAgents ?? [], workflows: center.library.runnable,
                onSave: { save($0) }, onCancel: { editing = nil }
            )
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: DS.Space.lg) {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text("Automations")
                    .font(.dsTitle2)
                    .foregroundStyle(.dsTextPrimary)
                Text("Tasks that start themselves: a prompt, a goal or a workflow, on a schedule or when something happens.")
                    .font(.dsBody)
                    .foregroundStyle(.dsTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .tracking(DS.Tracking.tight)
            Spacer(minLength: DS.Space.lg)
            if engine.automations.contains(where: { !$0.isPaused }) {
                Button("Pause All", systemImage: "pause.circle") {
                    for automation in engine.automations where !automation.isPaused {
                        engine.setPaused(true, for: automation.id)
                    }
                }
                .buttonStyle(.ds(.secondary, size: .medium))
            }
            Button("New Automation", systemImage: "plus") { startNew(from: nil) }
                .buttonStyle(.ds(.primary, size: .medium))
                .disabled(model.projects.all.isEmpty)
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(engine.automations) { automation in
                AutomationRow(
                    automation: automation, latest: engine.runs(of: automation.id).first, nextRun: engine.nextFire(of: automation),
                    onOpen: { path = [automation.id] }, onRunNow: { engine.runNow(automation.id) },
                    onTogglePause: { engine.setPaused(!automation.isPaused, for: automation.id) },
                    onEdit: { editing = Edit(automation: automation, isNew: false) },
                    onDelete: { engine.delete(automation.id) }
                )
                if automation.id != engine.automations.last?.id {
                    SeparatorLine()
                }
            }
        }
        .background(.dsSurface, in: .rect(cornerRadius: DS.Radius.card))
        .overlay { RoundedRectangle(cornerRadius: DS.Radius.card).strokeBorder(.dsSeparator, lineWidth: 1) }
    }

    private var templates: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            SectionHeader(engine.automations.isEmpty ? "Start from a template" : "Templates")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: AutomationMetrics.cardMinWidth), spacing: DS.Space.md, alignment: .top)], spacing: DS.Space.md) {
                ForEach(AutomationTemplate.all) { template in
                    AutomationTemplateCard(template: template) { startNew(from: template) }
                }
            }
            if model.projects.all.isEmpty {
                Text("Open a project first; automations work in a project's folder.")
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextTertiary)
            }
        }
    }

    @ViewBuilder private func detail(_ id: Automation.ID) -> some View {
        if let automation = engine.automations.first(where: { $0.id == id }) {
            AutomationDetailView(
                automation: automation, runs: engine.runs(of: id), nextRun: engine.nextFire(of: automation),
                agentName: automation.agent.flatMap { agent in center.host?.workflowAgents.first { $0.id == agent }?.name },
                onRunNow: { engine.runNow(id) }, onTogglePause: { engine.setPaused(!automation.isPaused, for: id) },
                onEdit: { editing = Edit(automation: automation, isNew: false) },
                onDelete: {
                    engine.delete(id)
                    path = []
                },
                onOpenRun: onOpenRun, onStopRun: { engine.stop($0) }
            )
            .navigationTitle(automation.name)
        } else {
            EmptyStateView("This Automation Is Gone", systemImage: "clock.arrow.circlepath")
        }
    }

    private func startNew(from template: AutomationTemplate?) {
        guard let project = model.currentProject?.url ?? model.projects.all.first?.url else { return }
        let automation = template?.automation(in: project, at: .now)
            ?? Automation(name: "", triggers: [.schedule(.daily(hour: 9, minute: 0))], action: .prompt(""), project: project, createdAt: .now)
        editing = Edit(automation: automation, isNew: true)
    }

    private func save(_ automation: Automation) {
        editing = nil
        // Making one is turning the feature on; an explicit choice is only recorded when it's off.
        let id = BuiltInPlugins.automations.manifest.id
        if !model.plugins.isEnabled(id) {
            model.plugins.setEnabled(true, for: id)
        }
        Task { await engine.save(automation) }
    }
}
