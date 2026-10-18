import Search
import SwiftUI

/// The filters under the search field: agent, project, kind and date as menus, and changed files
/// and archived tasks as toggles. The same filters work as operators typed in the query
/// (`agent:codex`), for keyboard use.
struct TranscriptSearchFilterBar: View {
    @Binding var filters: SearchFilters
    let agents: [AgentDefinition]
    let projects: [Project]

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            PillMenu(title(for: filters.agents, names: agents.map { ($0.id.rawValue, $0.displayName) }, any: "Agent")) {
                Button("Any Agent") { filters.agents = [] }
                Divider()
                ForEach(agents, id: \.id) { agent in
                    toggle(agent.displayName, isOn: filters.agents.contains(agent.id.rawValue)) {
                        filters.agents.formSymmetricDifference([agent.id.rawValue])
                    }
                }
            }
            PillMenu(title(for: filters.projects, names: projects.map { ($0.path, $0.name) }, any: "Project")) {
                Button("Any Project") { filters.projects = [] }
                Divider()
                ForEach(projects) { project in
                    toggle(project.name, isOn: filters.projects.contains(project.path)) {
                        filters.projects.formSymmetricDifference([project.path])
                    }
                }
            }
            PillMenu(kindTitle) {
                Button("Everything") {
                    filters.roles = []
                    filters.includeThinking = false
                }
                Divider()
                ForEach(TranscriptSearchKind.allCases, id: \.self) { kind in
                    toggle(kind.title, isOn: filters.roles.contains(kind.role)) {
                        filters.roles.formSymmetricDifference([kind.role])
                        filters.includeThinking = filters.roles.contains(.thought)
                    }
                }
            }
            PillMenu(TranscriptSearchDateRange(filters.after).title) {
                ForEach(TranscriptSearchDateRange.allCases, id: \.self) { range in
                    toggle(range.title, isOn: TranscriptSearchDateRange(filters.after) == range) {
                        filters.after = range.start(now: .now)
                        filters.before = nil
                    }
                }
            }
            Button {
                filters.hasDiff.toggle()
            } label: {
                Label("Changed Files", systemImage: "plusminus")
            }
            .buttonStyle(.pill(isOn: filters.hasDiff))
            Button {
                filters.includeArchived.toggle()
            } label: {
                Label("Archived", systemImage: "archivebox")
            }
            .buttonStyle(.pill(isOn: filters.includeArchived))
            Spacer(minLength: 0)
            if !filters.isEmpty {
                Button("Clear") { filters = SearchFilters() }
                    .buttonStyle(.ds(.ghost))
            }
        }
        .font(.dsCaption)
    }

    private var kindTitle: String {
        let kinds = TranscriptSearchKind.allCases.filter { filters.roles.contains($0.role) }
        return kinds.isEmpty ? "Kind" : kinds.map(\.title).joined(separator: ", ")
    }

    private func title(for selected: Set<String>, names: [(String, String)], any: String) -> String {
        let chosen = names.filter { selected.contains($0.0) }.map(\.1)
        switch chosen.count {
        case 0: return any
        case 1: return chosen[0]
        default: return "\(chosen[0]) +\(chosen.count - 1)"
        }
    }

    private func toggle(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if isOn {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }
}

/// The kinds of text the Kind filter picks from.
enum TranscriptSearchKind: CaseIterable {
    case prompts, replies, tools, plans, thinking

    var role: SearchRole {
        switch self {
        case .prompts: .user
        case .replies: .agent
        case .tools: .tool
        case .plans: .plan
        case .thinking: .thought
        }
    }

    var title: String {
        switch self {
        case .prompts: "Prompts"
        case .replies: "Replies"
        case .tools: "Commands & Files"
        case .plans: "Plans"
        case .thinking: "Thinking"
        }
    }
}

/// The date filter's choices, as a start date relative to now.
enum TranscriptSearchDateRange: CaseIterable {
    case anyTime, today, week, month, year

    init(_ after: Date?) {
        guard let after else {
            self = .anyTime
            return
        }
        let days = Date.now.timeIntervalSince(after) / 86_400
        self =
            switch days {
            case ..<1.5: .today
            case ..<8: .week
            case ..<32: .month
            default: .year
            }
    }

    var title: String {
        switch self {
        case .anyTime: "Any Time"
        case .today: "Today"
        case .week: "Past Week"
        case .month: "Past Month"
        case .year: "Past Year"
        }
    }

    func start(now: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .anyTime: nil
        case .today: calendar.startOfDay(for: now)
        case .week: calendar.date(byAdding: .day, value: -7, to: now)
        case .month: calendar.date(byAdding: .month, value: -1, to: now)
        case .year: calendar.date(byAdding: .year, value: -1, to: now)
        }
    }
}
