import SwiftUI
import TaskList

/// The Projects header's filter button: a menu (a popover on touch) of filters that combine freely,
/// by status, agent and checkout, plus including archived tasks and the sort. While filters are on,
/// the glyph fills and counts them.
struct SidebarFilterButton: View {
    @Environment(AppModel.self) private var model
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme
    @Binding var filter: TaskFilter
    @Binding var isSelecting: Bool

    @State private var isShowingPanel = false

    var body: some View {
        if DS.isTouchPlatform {
            Button {
                isShowingPanel = true
            } label: {
                label
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isShowingPanel) {
                SidebarFilterPanel(filter: $filter, isSelecting: $isSelecting, options: options)
                    .dsPopoverBackground()
            }
            .accessibilityLabel(accessibilityLabel)
        } else {
            Menu {
                ForEach(SidebarFilterOption.Section.allCases, id: \.self) { section in
                    Section(section.title) {
                        ForEach(options.filter { $0.section == section }) { option in
                            Toggle(isOn: option.isOn) {
                                Label {
                                    Text(option.title)
                                } icon: {
                                    // Menus only draw images.
                                    if let agent = option.agent {
                                        AgentIconStore.shared.image(
                                            for: agent, size: DS.Size.rowLeading, scale: displayScale,
                                            colorScheme: colorScheme)
                                    } else if let systemImage = option.systemImage {
                                        Image(systemName: systemImage)
                                    }
                                }
                            }
                        }
                    }
                }
                Picker("Sort By", selection: $filter.sort) {
                    ForEach(TaskFilter.Sort.allCases, id: \.self) { sort in
                        Text(sort.title).tag(sort)
                    }
                }
                .pickerStyle(.inline)
                Divider()
                Button("Clear All Filters") { filter.clearFilters() }
                    .disabled(filter.chips.isEmpty)
            } label: {
                label
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .labelStyle(.titleAndIcon)
            .help("Filter Tasks")
            .accessibilityLabel(accessibilityLabel)
        }
    }

    private var label: some View {
        HStack(spacing: DS.Space.xxs) {
            Image(systemName: filter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(filter.isActive ? .dsAccent : .dsTextSecondary)
            if !filter.chips.isEmpty {
                Text("\(filter.chips.count)")
                    .font(.dsMonoCaption)
                    .foregroundStyle(.dsAccent)
            }
        }
        .padding(.horizontal, DS.Space.xs)
        .frame(minWidth: DS.Size.controlXS, minHeight: DS.Size.controlXS)
        .background(filter.isActive ? .dsHover : .clear, in: .rect(cornerRadius: DS.Radius.control))
        .contentShape(.rect)
        .dsHitTarget(DS.Size.controlXS)
    }

    private var accessibilityLabel: String {
        filter.chips.isEmpty ? "Filter Tasks" : "Filter Tasks, \(filter.chips.count) on"
    }

    private var options: [SidebarFilterOption] {
        SidebarFilterOption.all(filter: $filter, agents: model.agents.map(\.agent))
    }
}

/// One filter the menu and the panel offer, with the binding that turns it on.
struct SidebarFilterOption: Identifiable {
    enum Section: CaseIterable {
        case status, agent, checkout, archive

        var title: String {
            switch self {
            case .status: "Status"
            case .agent: "Agent"
            case .checkout: "Checkout"
            case .archive: "Archive"
            }
        }
    }

    let id: String
    let section: Section
    let title: String
    var systemImage: String?
    var agent: AgentDefinition?
    let isOn: Binding<Bool>

    static func all(filter: Binding<TaskFilter>, agents: [AgentDefinition]) -> [SidebarFilterOption] {
        let statuses = TaskFilter.Status.allCases.map { status in
            SidebarFilterOption(
                id: "status.\(status.rawValue)", section: .status, title: status.title,
                systemImage: status.systemImage,
                isOn: Binding(
                    get: { filter.wrappedValue.statuses.contains(status) },
                    set: { _ in filter.wrappedValue.toggle(status) }))
        }
        let agentOptions = agents.map { agent in
            SidebarFilterOption(
                id: "agent.\(agent.id.rawValue)", section: .agent, title: agent.displayName, agent: agent,
                isOn: Binding(
                    get: { filter.wrappedValue.agents.contains(agent.id.rawValue) },
                    set: { _ in filter.wrappedValue.toggle(agent: agent.id.rawValue) }))
        }
        return statuses + agentOptions + [
            SidebarFilterOption(
                id: "changes", section: .checkout, title: "Has uncommitted changes",
                systemImage: "plusminus", isOn: filter.requiresUncommittedChanges),
            SidebarFilterOption(
                id: "pullRequest", section: .checkout, title: "Has a pull request",
                systemImage: "arrow.triangle.pull", isOn: filter.requiresPullRequest),
            SidebarFilterOption(
                id: "archived", section: .archive, title: "Include archived",
                systemImage: "archivebox", isOn: filter.includesArchived),
        ]
    }
}

extension TaskFilter.Status {
    var systemImage: String {
        switch self {
        case .needsYou: "exclamationmark.circle"
        case .running: "circle.dotted"
        case .unread: "circlebadge"
        case .done: "checkmark.circle"
        case .failed: "xmark.circle"
        }
    }
}

/// The filters on touch, where a menu would close after each one: rows that toggle, the sort, and
/// Select to pick tasks.
private struct SidebarFilterPanel: View {
    @Binding var filter: TaskFilter
    @Binding var isSelecting: Bool
    let options: [SidebarFilterOption]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                ForEach(SidebarFilterOption.Section.allCases, id: \.self) { section in
                    SectionHeader(section.title)
                    ForEach(options.filter { $0.section == section }) { option in
                        row(option.title, isOn: option.isOn.wrappedValue) {
                            if let agent = option.agent {
                                AgentIcon(agent: agent)
                            } else if let systemImage = option.systemImage {
                                Image(systemName: systemImage)
                            }
                        } action: {
                            option.isOn.wrappedValue.toggle()
                        }
                    }
                }
                SectionHeader("Sort By")
                ForEach(TaskFilter.Sort.allCases, id: \.self) { sort in
                    row(sort.title, isOn: filter.sort == sort) {
                        EmptyView()
                    } action: {
                        filter.sort = sort
                    }
                }
                SeparatorLine()
                HStack {
                    Button(isSelecting ? "Done Selecting" : "Select Tasks") { isSelecting.toggle() }
                    Spacer()
                    Button("Clear All") { filter.clearFilters() }
                        .disabled(filter.chips.isEmpty)
                }
                .buttonStyle(.ds(.ghost))
            }
            .padding(DS.Space.md)
        }
        .frame(width: DS.Size.sidebarWidth, height: DS.Size.sidebarWidth * 2)
    }

    private func row(
        _ title: String, isOn: Bool, @ViewBuilder icon: () -> some View, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: DS.Space.sm) {
                icon()
                    .foregroundStyle(.dsTextSecondary)
                    .frame(width: DS.Size.rowLeading, height: DS.Size.rowLeading)
                Text(title)
                    .font(.dsCallout)
                    .foregroundStyle(.dsTextPrimary)
                Spacer(minLength: 0)
                if isOn {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.dsAccent)
                }
            }
            .frame(minHeight: DS.Size.minimumHitTarget)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

#if DEBUG
#Preview("Filter button") {
    let app = AppModel.preview()
    DSPreviewPair {
        HStack(spacing: DS.Space.lg) {
            SidebarFilterButton(filter: .constant(TaskFilter()), isSelecting: .constant(false))
            SidebarFilterButton(filter: .constant(SidebarPreviewFixtures.filtered), isSelecting: .constant(false))
        }
    }
    .sidebarPreviewEnvironment(app)
}

#Preview("Filter panel (touch)") {
    let app = AppModel.preview()
    DSPreviewPair {
        SidebarFilterPanel(
            filter: .constant(SidebarPreviewFixtures.filtered), isSelecting: .constant(false),
            options: SidebarFilterOption.all(
                filter: .constant(SidebarPreviewFixtures.filtered), agents: app.agents.map(\.agent))
        )
        .dsPopoverBackground()
    }
    .sidebarPreviewEnvironment(app)
}
#endif
