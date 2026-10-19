#if canImport(Skills)
import Skills
import SwiftUI

/// The page's lists: Native's own skills, the user's and projects' skills, and the ones agents
/// bring themselves (their plugins and built-ins), filtered by the page's filter.
struct SkillsSections: View {
    let library: SkillLibrary
    let project: URL?
    let filter: String
    @Binding var expanded: Set<String>
    let onInstall: () -> Void
    let onUpdate: (SkillItem) -> Void
    let onRemove: (SkillItem) -> Void
    let onToggle: (SkillItem, Bool) -> Void
    let onToggleNative: (NativeSkillListing, Bool) -> Void

    private var terms: [String] {
        filter.lowercased().split(separator: " ").map(String.init)
    }

    private func matches(_ texts: String?...) -> Bool {
        let haystack = texts.compactMap(\.self).joined(separator: " ").lowercased()
        return terms.allSatisfy(haystack.contains)
    }

    /// Skills that belong to the selected project, or to no project (shown everywhere).
    private var visible: [SkillItem] {
        library.items.filter { item in
            item.places.contains { place in
                guard let owner = place.root.scope.project else { return true }
                return project.map { SkillPaths.key($0) == SkillPaths.key(owner) } ?? true
            } && matches(item.name, item.description)
        }
    }

    var body: some View {
        let native = library.nativeSkills.filter { matches($0.id, $0.summary) }
        let own = visible.filter { $0.scopes.contains { $0.isUserManaged || $0 == .account } }
        let agents = visible.filter { !own.contains($0) }
        if !native.isEmpty {
            section("Native's skills", note: "Native serves these to every agent through its MCP tools.") {
                ForEach(native) { skill in
                    SkillNativeRow(library: library, skill: skill, project: project) { onToggleNative(skill, $0) }
                }
            }
        }
        section(
            "Your skills",
            note: "In your skills folders and your projects'. Several agents can share one; it's listed once."
        ) {
            if own.isEmpty {
                MCPEmptyRow(
                    title: emptyTitle, message: emptyMessage, actionTitle: terms.isEmpty ? "Install Skill" : nil,
                    action: onInstall)
            } else {
                ForEach(own) { row($0) }
            }
        }
        if !agents.isEmpty {
            section(
                "From your agents", note: "Shipped with an agent or one of its plugins, which keep them up to date."
            ) {
                ForEach(agents) { row($0) }
            }
        }
    }

    private var emptyTitle: String {
        if !terms.isEmpty { return "No skills match \"\(filter)\"" }
        return library.isReading ? "Reading your agents' skills…" : "No skills yet"
    }

    private var emptyMessage: String {
        if !terms.isEmpty { return "Try another word, or clear the filter." }
        return
            "A skill is a folder with a SKILL.md. Install one from a git repository, skills.sh or a folder, and every agent you choose loads it."
    }

    private func row(_ item: SkillItem) -> some View {
        SkillRow(
            library: library, item: item, project: project,
            isExpanded: Binding(
                get: { expanded.contains(item.key) },
                set: { if $0 { expanded.insert(item.key) } else { expanded.remove(item.key) } }),
            onUpdate: { onUpdate(item) }, onRemove: { onRemove(item) }, onToggle: { onToggle(item, $0) })
    }

    private func section<Content: View>(
        _ title: String, note: String, @ViewBuilder content: () -> Content
    )
        -> some View
    {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            SettingsSubheading(title, note: note)
            SettingsRowGroup { content() }
        }
    }
}

/// One of Native's own skills: what it's for and whether agents see it.
struct SkillNativeRow: View {
    let library: SkillLibrary
    let skill: NativeSkillListing
    let project: URL?
    let onToggle: @MainActor (Bool) -> Void

    var body: some View {
        let isOn = library.mode(of: SkillItem.key(for: skill.id), in: project) == .on
        SettingsRow(
            id: SkillsSettingsPage.rowID(SkillItem.key(for: skill.id)),
            title: Text(skill.id),
            description: Text(SkillRow.summary(skill.summary)),
            detail: Text(
                skill.isServed
                    ? "Every agent, through Native's MCP tools · from \(skill.pluginName)"
                    : "\(skill.pluginName) is off, so agents don't see it. Turn it on in Settings ▸ Extensions.")
        ) {
            Badge("Native")
        } control: {
            SettingsSwitch(skill.id, isOn: Binding(get: { isOn }, set: onToggle))
        }
    }
}
#endif
