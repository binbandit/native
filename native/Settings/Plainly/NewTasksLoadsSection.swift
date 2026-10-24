import ACP
import NativePolicy
import SwiftUI
import TaskDefaults

struct NewTasksLoadsSection: View {
    let inventory: NewTasksLoadsModel
    var window: Int?
    var report: ContextReport?
    var fixtureItems: [NewTasksLoadItem]?
    @Environment(SettingsPresentation.self) private var presentation
    @Environment(PolicyCenter.self) private var policyCenter: PolicyCenter?
    @State private var expanded: Set<TaskContextBudget.Part.Kind> = []
    @State private var inspected: NewTasksLoadItem?
    @State private var change: NewTasksLoadItem?
    @State private var width = DS.Settings.pageWidth

    private var items: [NewTasksLoadItem] {
        if let fixtureItems { return fixtureItems }
        return
            (inventory.instructionItems + inventory.serverItems(policy: policy) + inventory.skillItems(policy: policy))
            .map { item in
                var counted = item
                switch item.kind {
                case .tools:
                    if let cost = report?.mcpServers.first(where: { $0.name == item.name }) {
                        counted.tokens = cost.tokens
                    }
                case .skills:
                    if let cost = report?.skills.first(where: { $0.name == item.name }) {
                        counted.tokens = cost.tokens.value
                    }
                case .instructions:
                    if let file = report?.memoryFiles.first(where: { URL(filePath: $0.path).absoluteString == item.id })
                    {
                        counted.tokens = file.tokens
                    }
                }
                return counted
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            SettingsGroup(title: "What it loads") {
                if items.contains(where: { expanded.contains($0.kind) }) {
                    // Over the rows' token column: past the control slot and the gap before it.
                    Text("tokens").font(DS.Settings.caption).foregroundStyle(.dsTextTertiary)
                        .padding(.trailing, DS.Settings.rowInset + DS.Settings.loadControlSlot + DS.Space.md)
                }
            } content: {
                ForEach([TaskContextBudget.Part.Kind.instructions, .skills, .tools], id: \.self) { kind in
                    let group = items.filter { $0.kind == kind }
                    SettingsRow(title(kind)) {
                        Button {
                            if expanded.contains(kind) { expanded.remove(kind) } else { expanded.insert(kind) }
                        } label: {
                            HStack(spacing: DS.Space.sm) {
                                if let origin = origin(of: group) {
                                    HStack(spacing: DS.Space.xs) {
                                        if let symbol = origin.symbol { Image(systemName: symbol) }
                                        Text(origin.text)
                                    }
                                    .font(DS.Settings.caption).foregroundStyle(.dsTextTertiary)
                                }
                                Text(summary(group, kind: kind)).foregroundStyle(.dsTextSecondary)
                                Image(systemName: expanded.contains(kind) ? "chevron.down" : "chevron.right")
                                    .font(.dsMicro).foregroundStyle(.dsTextSecondary)
                            }
                            .font(DS.Settings.body)
                            .lineLimit(1)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        .buttonStyle(.plain)
                        .dsHitTarget(DS.Settings.controlHeight)
                        .accessibilityLabel(
                            "\(title(kind)), \(summary(group, kind: kind))\(origin(of: group).map { ", \($0.text)" } ?? "")"
                        )
                    }
                    if expanded.contains(kind) {
                        if group.isEmpty {
                            VStack(alignment: .leading, spacing: DS.Space.sm) {
                                Text(emptyNote(kind)).font(DS.Settings.caption).foregroundStyle(.dsTextSecondary)
                                if kind != .instructions {
                                    Button("Open \(kind == .tools ? "MCP Servers" : "Skills")…") { openLibrary(kind) }
                                        .buttonStyle(.settings)
                                }
                            }
                        }
                        ForEach(group) { item in
                            NewTasksLoadRow(
                                item: item, sourceSymbol: inventory.symbol(forSource: item.source, policy: policy),
                                onInspect: { inspected = item },
                                onSwitch: { value in
                                    item.setEnabled?(value)
                                    change = item
                                },
                                onReview: { openLibrary(item.kind) }
                            )
                            .contextMenu {
                                if case .switchable = item.control {
                                    Button("Reset") {
                                        item.reset?(); change = nil
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .modifier(NewTasksNarrowing(width: width))
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: {
                width = $0
            }
            if let change {
                HStack {
                    Text("Changed \(change.name) for \(inventory.project?.name ?? "all projects").")
                        .font(DS.Settings.caption).foregroundStyle(.dsTextSecondary)
                    Button("Undo") {
                        change.undo?(); self.change = nil
                    }.buttonStyle(.plain)
                }
            }
            NewTasksContextBudget(
                budget: .init(
                    parts: items.map { .init($0.kind, tokens: $0.tokens, included: $0.included) }
                        + (fixtureItems == nil ? builtInParts : []), window: window))
        }
        .preference(
            key: NewTasksOrganizationCount.self,
            value: items.filter { $0.source == policy.organizationDisplayName }.count
        )
        .popover(item: $inspected) { item in
            NewTasksSourceStack(
                receipt: item.receipt
                    ?? NewTasksSettingReceipt(
                        title: item.name, context: "for \(inventory.agent.name)",
                        value: item.included ? "Included" : "Not included",
                        source: .agent(inventory.agent.name),
                        layers: [.init(name: item.source, symbol: "doc", value: item.name, wins: true)],
                        note: item.detail
                            ?? "The agent loads this from its own configuration. Native does not edit that file."))
        }
        .onAppear { if inventory.project != nil { expanded = Set(TaskContextBudget.Part.Kind.allCases) } }
    }

    private var builtInParts: [TaskContextBudget.Part] {
        guard let report else { return [.init(.instructions, tokens: nil)] }
        return report.usedCategories.filter { ContextGroup(category: $0.name) == .builtIn }.map {
            .init($0.name.localizedCaseInsensitiveContains("tool") ? .tools : .instructions, tokens: $0.tokens)
        }
    }

    private func title(_ kind: TaskContextBudget.Part.Kind) -> String {
        switch kind {
        case .instructions: "Instructions";
        case .skills: "Skills";
        case .tools: "MCP servers"
        }
    }

    private func summary(_ group: [NewTasksLoadItem], kind: TaskContextBudget.Part.Kind) -> String {
        if kind == .instructions, inventory.isReading { return "Reading…" }
        if group.isEmpty { return kind == .instructions ? "Not reported" : "None listed" }
        let count = "\(group.filter(\.included).count) on"
        let sources = Set(group.map(\.source)).count
        return sources > 1 ? "\(count) · \(sources) sources" : count
    }

    /// A single source keeps its glyph; multiple sources are counted in the summary and named
    /// in the expanded rows.
    private func origin(of group: [NewTasksLoadItem]) -> (symbol: String?, text: String)? {
        let sources = Set(group.map(\.source))
        guard let only = sources.first else { return nil }
        guard sources.count == 1 else { return nil }
        return (inventory.symbol(forSource: only, policy: policy), only)
    }

    private var policy: NativePolicy { policyCenter?.policy ?? PolicyCenter.shared.policy }

    private func emptyNote(_ kind: TaskContextBudget.Part.Kind) -> String {
        switch kind {
        case .instructions:
            "No declared instruction files were found. The agent may load additional, inherited or conditional files."
        case .tools:
            inventory.mcp == nil
                ? "MCP Servers is off in Features. The agent may still load its own servers."
                : "No servers are listed for this agent and project."
        case .skills:
            inventory.skills == nil
                ? "Skills is off in Features. The agent may still load its own skills."
                : "No skills are listed for this agent and project."
        }
    }

    private func openLibrary(_ kind: TaskContextBudget.Part.Kind) {
        let pane: SettingsPane.ID = kind == .tools ? .mcpServers : .skills
        if (kind == .tools && inventory.mcp == nil) || (kind == .skills && inventory.skills == nil) {
            presentation.open(.extensions)
        } else if let project = inventory.project {
            presentation.open(pane, scopedTo: project.url)
        } else {
            presentation.open(pane)
        }
    }
}

#if DEBUG
#Preview("New Tasks - Loaded, failed, off and required") {
    let app = AppModel.preview()
    DSPreviewPair {
        NewTasksLoadsSection(
            inventory: NewTasksLoadsModel(
                agent: BuiltInPlugins.codex.manifest.agents[0], project: app.previewProject(), registry: app.plugins),
            window: 200000,
            fixtureItems: NewTasksPreviewFixtures.items(project: "pier", organization: "Northwind Federal IT")
        ).settingsPreviewPage()
    }.environment(SettingsPresentation()).environment(\.settingsPlainly, true)
}
#endif
