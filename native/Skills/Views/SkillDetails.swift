#if canImport(Skills)
import Skills
import SwiftUI

/// What's behind a skill's row: every place it is and who reads it, what its SKILL.md declares,
/// what's wrong with it, where Native installed it from, and the files in it.
struct SkillDetails: View {
    let library: SkillLibrary
    let item: SkillItem

    @State private var files: [SkillFile]?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            if let description = item.description, SkillRow.summary(description) != description {
                group("Description") {
                    Text(description)
                        .settingsText(.caption)
                        .foregroundStyle(.dsTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            group("Where it is") {
                ForEach(item.places) { place in
                    placeRow(place)
                }
            }
            if !facts.isEmpty {
                group("What it declares") {
                    ForEach(facts, id: \.0) { label, value in
                        line(label, value)
                    }
                }
            }
            if !item.problems.isEmpty {
                group("Problems") {
                    ForEach(item.problems, id: \.self) { problem in
                        Text(problem.message)
                            .settingsText(.caption)
                            .foregroundStyle(problem.severity == .error ? .dsDanger : .dsWarning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if let record = library.record(for: item) {
                group("Installed by Native") {
                    line("From", record.source.displayText)
                    if let revision = record.revision { line("Commit", String(revision.prefix(12))) }
                    line("On", record.installedAt.formatted(date: .abbreviated, time: .shortened))
                }
            }
            group("Files") {
                if let files {
                    SkillFileList(files: files)
                } else {
                    DotGridLoader(pattern: .waiting)
                }
            }
        }
        .padding(DS.Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.dsSurfaceSunken, in: .rect(cornerRadius: DS.Radius.card, style: .continuous))
        .task(id: item.primary.resolvedPath) {
            let scanner = SkillScanner(files: library.files)
            let path = item.primary.path
            files = await Task.detached { scanner.contents(of: path) }.value
        }
    }

    private var facts: [(String, String)] {
        guard let frontmatter = item.primary.document?.frontmatter else { return [] }
        var facts: [(String, String)] = []
        if let version = frontmatter.version { facts.append(("Version", version)) }
        if let license = frontmatter.license { facts.append(("License", license)) }
        if let compatibility = frontmatter.compatibility { facts.append(("Needs", compatibility)) }
        if !frontmatter.allowedTools.isEmpty {
            facts.append(("Tools it may use", frontmatter.allowedTools.joined(separator: ", ")))
        }
        if !frontmatter.isModelInvocable { facts.append(("Invoked", "Only when you run it as a command")) }
        if !frontmatter.isUserInvocable { facts.append(("Invoked", "Only by the agent, not as a command")) }
        return facts
    }

    private func placeRow(_ place: SkillFolder) -> some View {
        let readers = library.agents.filter { place.root.agents.contains($0.format) }.map(\.name)
        return HStack(alignment: .firstTextBaseline, spacing: DS.Space.md) {
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(SkillPaths.abbreviated(place.path, home: library.home))
                    .font(SettingsTextStyle.mono.font)
                    .foregroundStyle(.dsTextPrimary)
                    .textSelection(.enabled)
                Text(
                    ([
                        place.root.scope.displayName,
                        readers.isEmpty ? "No agent reads it" : readers.joined(separator: ", "),
                    ]
                        + (place.isLink
                            ? ["Links to " + SkillPaths.abbreviated(place.resolvedPath, home: library.home)] : []))
                        .joined(separator: " · ")
                )
                .settingsText(.caption)
                .foregroundStyle(.dsTextTertiary)
            }
            Spacer(minLength: DS.Space.md)
            if PlatformFileBrowser.canReveal {
                Button("Show") { PlatformFileBrowser.reveal(URL(filePath: place.path)) }
                    .buttonStyle(.ds(.ghost, size: .small))
                    .accessibilityLabel("Show \(place.path) in Finder")
            }
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text(title)
                .settingsText(.caption)
                .foregroundStyle(.dsTextSecondary)
            content()
        }
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.md) {
            Text(label)
                .settingsText(.caption)
                .foregroundStyle(.dsTextTertiary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .settingsText(.caption)
                .foregroundStyle(.dsTextPrimary)
                .textSelection(.enabled)
        }
    }
}

/// A skill's files, scripts first and marked, each openable to read.
struct SkillFileList: View {
    let files: [SkillFile]
    @State private var open: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            if files.isEmpty {
                Text("No files.")
                    .settingsText(.caption)
                    .foregroundStyle(.dsTextTertiary)
            }
            ForEach(files) { file in
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Button {
                        if open.contains(file.id) { open.remove(file.id) } else { open.insert(file.id) }
                    } label: {
                        HStack(spacing: DS.Space.md) {
                            Image(systemName: open.contains(file.id) ? "chevron.down" : "chevron.right")
                                .foregroundStyle(.dsTextTertiary)
                            Text(file.relativePath)
                                .font(SettingsTextStyle.mono.font)
                                .foregroundStyle(.dsTextPrimary)
                            if file.isScript { Badge("Script", tone: .warning) }
                            Spacer(minLength: DS.Space.md)
                            Text(DSFormat.memory(UInt64(file.size)))
                                .settingsText(.caption)
                                .foregroundStyle(.dsTextTertiary)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(file.text == nil)
                    if open.contains(file.id), let text = file.text {
                        CappedHeightScrollView(maxHeight: 220) {
                            Text(text)
                                .font(.dsMono)
                                .foregroundStyle(.dsTextSecondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(DS.Space.md)
                        }
                        .background(.dsBackground, in: .rect(cornerRadius: DS.Radius.row, style: .continuous))
                    }
                }
            }
        }
    }
}

/// Every folder Native reads skills from, with the agents that read each.
struct SkillFoldersFooter: View {
    let library: SkillLibrary

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            SettingsSubheading(
                "Skills folders", note: "Where your agents look. A folder that doesn't exist yet is fine.")
            ForEach(library.roots.filter { $0.scope.isUserManaged }, id: \.path) { root in
                HStack(spacing: DS.Space.md) {
                    Text(SkillPaths.abbreviated(root.path, home: library.home))
                        .font(SettingsTextStyle.mono.font)
                        .foregroundStyle(.dsTextPrimary)
                        .textSelection(.enabled)
                    Text(library.agents.filter { root.agents.contains($0.format) }.map(\.name).joined(separator: ", "))
                        .settingsText(.caption)
                        .foregroundStyle(.dsTextTertiary)
                    Spacer(minLength: DS.Space.md)
                }
            }
            let unsupported = library.agents.filter { $0.switching == .unsupported }
            if !unsupported.isEmpty {
                Text(
                    "\(unsupported.map(\.name).joined(separator: ", ")) can't leave a skill out of a session, so switches here don't reach \(unsupported.count == 1 ? "it" : "them"). Native never moves or edits skill files to turn one off."
                )
                .settingsText(.caption)
                .foregroundStyle(.dsTextTertiary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
#endif
