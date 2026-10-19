import SwiftUI

/// "Where agents look for …": reference, so it starts collapsed behind one summary row. Opened, the
/// folders are grouped by scope, one row each with a short path, what it holds and the agents that
/// read it; ones that don't exist yet wait behind their own button. Skills and MCP Servers both use
/// it, so the two pages list where agents read from the same way.
struct SettingsFoldersSection<Footer: View>: View {
    let title: String
    let folders: [SettingsFolder]
    /// What a row is ("folder", "file").
    let place: SettingsFolderNoun
    /// What a row holds ("skill", "server").
    let item: SettingsFolderNoun
    /// Anything else about where agents read from, under the folders while they're open.
    @ViewBuilder var footer: Footer

    @State private var isExpanded = false
    @State private var showsMissing = false

    var body: some View {
        if !folders.isEmpty {
            section
        }
    }

    private var section: some View {
        let missing = folders.count { !$0.exists }
        return VStack(alignment: .leading, spacing: DS.Space.lg) {
            SettingsRow(title, description: Text(summary)) {
                IconButton(
                    isExpanded ? "Hide Details" : "Show Details",
                    systemImage: isExpanded ? "chevron.up" : "chevron.down", size: .medium, isActive: isExpanded
                ) {
                    withAnimation(.dsDisclosure) { isExpanded.toggle() }
                }
                .accessibilityLabel(
                    "\(isExpanded ? "Hide" : "Show") details for \(item.one) \(place.many)")
            }
            if isExpanded {
                VStack(alignment: .leading, spacing: DS.Space.xl) {
                    ForEach(SettingsFolder.Scope.allCases, id: \.self) { scope in
                        sections(folders.filter { $0.scope == scope && ($0.exists || showsMissing) })
                    }
                    if missing > 0 {
                        Button(
                            showsMissing
                                ? "Hide \(place.many) that don't exist"
                                : "Show \(place.many) that don't exist yet (\(missing))"
                        ) {
                            withAnimation(.dsDisclosure) { showsMissing.toggle() }
                        }
                        .buttonStyle(.ds(.ghost, size: .small))
                        // Out by the ghost button's padding, so its text lines up with the paths above.
                        .padding(.leading, -DS.Space.lg)
                    }
                    footer
                }
                .transition(.opacity)
            }
        }
    }

    /// "2 folders with skills · 9 more checked".
    private var summary: String {
        let holding = folders.count { $0.exists && $0.itemCount > 0 }
        let first = "\(place.counted(holding)) with \(item.many)"
        let others = folders.count - holding
        return others > 0 ? "\(first) · \(others) more checked" : first
    }

    @ViewBuilder
    private func sections(_ folders: [SettingsFolder]) -> some View {
        let bySection = Dictionary(grouping: folders, by: \.section)
        ForEach(bySection.keys.sorted(), id: \.self) { section in
            VStack(alignment: .leading, spacing: DS.Space.md) {
                Text(section)
                    .settingsText(.caption)
                    .foregroundStyle(.dsTextSecondary)
                // A dense list: reference rows, not settings, so they sit closer than settings rows.
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array((bySection[section] ?? []).enumerated()), id: \.element.id) { index, folder in
                        if index > 0 { SeparatorLine() }
                        SettingsFolderRow(folder: folder, item: item)
                    }
                }
            }
        }
    }
}

extension SettingsFoldersSection where Footer == EmptyView {
    init(title: String, folders: [SettingsFolder], place: SettingsFolderNoun, item: SettingsFolderNoun) {
        self.init(title: title, folders: folders, place: place, item: item) { EmptyView() }
    }
}

/// A noun a folders section counts: "1 skill", "3 skills".
struct SettingsFolderNoun: Hashable {
    let one: String
    let many: String

    init(_ one: String, plural: String? = nil) {
        self.one = one
        many = plural ?? one + "s"
    }

    func counted(_ count: Int) -> String {
        count == 1 ? "1 \(one)" : "\(count) \(many)"
    }
}

/// One folder: its short path, what it holds and anything wrong in it, the agents that read it as
/// glyphs, and Show in Finder on hover, in the context menu, or always where there's no hover.
private struct SettingsFolderRow: View {
    let folder: SettingsFolder
    let item: SettingsFolderNoun

    @State private var isHovered = false

    private var contents: String {
        guard folder.exists else { return "not created" }
        return folder.itemCount == 0 ? "no \(item.many)" : item.counted(folder.itemCount)
    }

    private var revealPath: String? {
        guard PlatformFileBrowser.canReveal, folder.exists else { return nil }
        return folder.paths.first
    }

    var body: some View {
        HStack(spacing: DS.Space.lg) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Space.md) {
                    Text(folder.label)
                        .settingsText(.mono)
                        .foregroundStyle(folder.exists ? .dsTextSecondary : .dsTextTertiary)
                        .textSelection(.enabled)
                        .help(folder.paths.joined(separator: "\n"))
                    Text(contents)
                        .settingsText(.caption)
                        .foregroundStyle(.dsTextTertiary)
                }
                if let problem = folder.problem {
                    Text(problem)
                        .settingsText(.caption)
                        .foregroundStyle(.dsDanger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: DS.Space.md)
            if let revealPath, isHovered || DS.isTouchPlatform {
                Button("Show") { PlatformFileBrowser.reveal(URL(filePath: revealPath)) }
                    .buttonStyle(.ds(.ghost, size: .small))
                    .accessibilityLabel("Show \(folder.label) in Finder")
            }
            HStack(spacing: DS.Space.xs) {
                ForEach(folder.readers) { agent in
                    AgentIcon(agent: agent)
                        .help(agent.displayName)
                        .accessibilityLabel(agent.displayName)
                }
            }
        }
        .frame(minHeight: DS.Size.rowMinHeight)
        .contentShape(.rect)
        .trackHover($isHovered)
        .contextMenu {
            if let revealPath {
                Button("Show in Finder") { PlatformFileBrowser.reveal(URL(filePath: revealPath)) }
            }
        }
    }
}
