#if canImport(Skills)
import Skills
import SwiftUI

/// One skill however many places have it: its switch, where it lives, which agents load it, and
/// what's wrong with it or where a switch can't reach.
struct SkillRow: View {
    let library: SkillLibrary
    let item: SkillItem
    let project: URL?
    @Binding var isExpanded: Bool
    let onUpdate: () -> Void
    let onRemove: () -> Void
    let onToggle: (Bool) -> Void

    private var isOn: Bool {
        library.mode(of: item.key, in: project) == .on
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            SettingsRow(
                id: SkillsSettingsPage.rowID(item.key),
                title: Text(item.name),
                description: Text(
                    item.description.map(Self.summary) ?? item.problems.first?.message ?? "No description."),
                detail: detail
            ) {
                ForEach(item.scopes, id: \.self) { scope in
                    Badge(scope.displayName)
                }
                if item.hasErrors {
                    Badge("Broken", tone: .danger)
                } else if item.problems.contains(where: { if case .duplicate = $0 { true } else { false } }) {
                    Badge("Duplicate", tone: .warning)
                }
            } control: {
                HStack(spacing: DS.Space.md) {
                    MCPExpandButton(isExpanded: $isExpanded, name: item.name)
                    menu
                    SettingsSwitch(item.name, isOn: Binding(get: { isOn }, set: onToggle))
                }
            }
            if isExpanded {
                SkillDetails(library: library, item: item)
            }
        }
    }

    /// A description's first sentence, so long ones don't turn rows into paragraphs; the details
    /// show the rest.
    static func summary(_ description: String) -> String {
        let limit = 160
        let sentence =
            description.firstRange(of: /[.!?](\s|$)/).map { String(description[..<$0.upperBound]) } ?? description
        let text = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.count > limit ? text.prefix(limit).trimmingCharacters(in: .whitespaces) + "…" : text
    }

    /// Who loads it, then anything that keeps the switch from reaching an agent.
    private var detail: Text {
        let agents = library.agents.filter { item.agents.contains($0.format) }.map(\.name)
        var parts = [agents.isEmpty ? "No agent loads it" : agents.joined(separator: ", ")]
        if item.distinctFolders.count > 1 { parts.append("\(item.distinctFolders.count) copies") }
        let overrides = library.switches.projectOverrides(for: item.key)
        if project == nil, !overrides.isEmpty {
            let names = overrides.keys.map { URL(filePath: $0).lastPathComponent }.sorted()
            parts.append("\(overrides.values.first == .off ? "Off" : "On") in \(names.joined(separator: ", "))")
        }
        var text = Text(parts.joined(separator: " · "))
        if !isOn || !library.switches.projectOverrides(for: item.key).isEmpty {
            for limitation in library.limitations(of: item) {
                text = text + Text("\n" + limitation).foregroundStyle(.dsWarning)
            }
        }
        if let problem = item.problems.first(where: { $0.severity == .error }), item.description != nil {
            text = text + Text("\n" + problem.message).foregroundStyle(.dsDanger)
        }
        return text
    }

    private var menu: some View {
        Menu {
            if library.record(for: item) != nil {
                Button("Update…", action: onUpdate)
            }
            if PlatformFileBrowser.canReveal {
                Button("Show in Finder") {
                    PlatformFileBrowser.reveal(URL(filePath: item.primary.path))
                }
            }
            if item.isUserManaged {
                Divider()
                Button("Remove…", role: .destructive, action: onRemove)
            }
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: DS.Size.controlSM, height: DS.Size.controlSM)
                .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.ds(.ghost, size: .medium))
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Actions for \(item.name)")
    }
}
#endif
