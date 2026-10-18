import Search
import SwiftUI

/// One selectable line of the results: a task, or one of its hits.
enum TranscriptSearchRow: Identifiable, Hashable {
    case task(SearchGroup)
    case hit(SearchGroup, SearchHit)

    var id: String {
        switch self {
        case .task(let group): "task-\(group.session.key.agent)/\(group.session.key.session)"
        case .hit(_, let hit): "hit-\(hit.id)"
        }
    }

    var group: SearchGroup {
        switch self {
        case .task(let group), .hit(let group, _): group
        }
    }

    var hit: SearchHit? {
        if case .hit(_, let hit) = self { hit } else { nil }
    }

    /// The rows in the order the keyboard moves through them.
    static func rows(of groups: [SearchGroup]) -> [Self] {
        groups.flatMap { group in [.task(group)] + group.hits.map { .hit(group, $0) } }
    }
}

/// Results grouped by task: the task (agent, title, project, when) and under it its best hits,
/// each with who said it and the matched words highlighted.
struct TranscriptSearchResultsList: View {
    let groups: [SearchGroup]
    @Binding var selection: TranscriptSearchRow.ID?
    let open: (TranscriptSearchRow) -> Void

    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(groups) { group in
                        row(.task(group))
                            .padding(.top, group.id == groups.first?.id ? 0 : DS.Space.sm)
                        ForEach(group.hits) { hit in
                            row(.hit(group, hit))
                        }
                    }
                }
                .padding(DS.Space.sm)
            }
            .onChange(of: selection) { _, selection in
                guard let selection else { return }
                proxy.scrollTo(selection)
            }
        }
    }

    private func row(_ row: TranscriptSearchRow) -> some View {
        Button {
            open(row)
        } label: {
            Group {
                switch row {
                case .task(let group): taskLabel(group)
                case .hit(_, let hit): hitLabel(hit)
                }
            }
            .padding(.horizontal, DS.Space.md)
            .padding(.vertical, DS.Space.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(row.id == selection ? Color.dsSelected : .clear, in: .rect(cornerRadius: DS.Radius.row))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .id(row.id)
        .onHover { isHovered in
            if isHovered { selection = row.id }
        }
        .accessibilityAddTraits(row.id == selection ? .isSelected : [])
    }

    private func taskLabel(_ group: SearchGroup) -> some View {
        let session = group.session
        return HStack(spacing: DS.Space.md) {
            agentIcon(session.key.agent)
            Text(session.title ?? "Untitled task")
                .font(.dsBodyMedium)
                .foregroundStyle(.dsTextPrimary)
                .lineLimit(1)
            if session.isArchived {
                Badge("Archived")
            }
            Spacer(minLength: DS.Space.md)
            Text(details(of: group))
                .font(.dsCaption)
                .foregroundStyle(.dsTextTertiary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private func hitLabel(_ hit: SearchHit) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.md) {
            Text(Self.title(of: hit.role))
                .font(.dsCaption)
                .foregroundStyle(.dsTextTertiary)
                .frame(width: TranscriptSearchMetrics.roleColumn, alignment: .leading)
            Self.text(hit.snippet)
                .font(.dsBody)
                .foregroundStyle(.dsTextSecondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if hit.hasDiff {
                Image(systemName: "plusminus")
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextTertiary)
                    .help("Changed files")
                    .accessibilityLabel("Changed files")
            }
        }
        // Hits sit under their task's title, past its icon.
        .padding(.leading, DS.Size.rowLeading + DS.Space.md)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func agentIcon(_ agent: String) -> some View {
        if let definition = model.plugins.agent(AgentDefinition.ID(rawValue: agent)) {
            AgentIcon(agent: definition)
        } else {
            Image(systemName: "sparkle")
                .font(.dsCaption)
                .foregroundStyle(.dsTextTertiary)
                .frame(width: DS.Size.rowLeading, height: DS.Size.rowLeading)
        }
    }

    private func details(of group: SearchGroup) -> String {
        var parts = [group.session.projectName]
        if let updated = group.session.updatedAt {
            parts.append(DSFormat.compactAge(updated, now: .now))
        }
        if group.hitCount > group.hits.count {
            parts.append("\(group.hitCount) matches")
        }
        return parts.joined(separator: " · ")
    }

    static func title(of role: SearchRole) -> String {
        switch role {
        case .user: "You"
        case .agent: "Agent"
        case .thought: "Thinking"
        case .tool: "Tool"
        case .plan: "Plan"
        case .title: "Task"
        }
    }

    /// The snippet with its matched words in the primary color on the accent's tint.
    static func text(_ snippet: SearchSnippet) -> Text {
        var string = AttributedString()
        for run in snippet.runs {
            var part = AttributedString(run.text)
            if run.isMatch {
                part.foregroundColor = .dsTextPrimary
                part.backgroundColor = .dsAccentSubtle
            }
            string += part
        }
        return Text(string)
    }
}

enum TranscriptSearchMetrics {
    /// The panel's size where it's a window-sized sheet (Mac, iPad).
    static let panelWidth: CGFloat = 720
    static let panelHeight: CGFloat = 560
    /// Room for the longest role label ("Thinking").
    static let roleColumn: CGFloat = 56
}
