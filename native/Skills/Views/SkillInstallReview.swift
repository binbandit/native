#if canImport(Skills)
import Skills
import SwiftUI

/// A fetched skill, before installing: its SKILL.md and scripts, which agents get it, where, and
/// the exact folders Native will write.
struct SkillInstallReview: View {
    let library: SkillLibrary
    let stage: SkillStage
    let project: URL?
    let isInstalling: Bool
    let error: String?
    let onBack: () -> Void
    let onCancel: () -> Void
    let onInstall: (StagedSkill, [SkillInstallTarget], String) -> Void

    @State private var selectedPath = ""
    @State private var chosenAgents: Set<SkillAgentFormat> = []
    @State private var scopePath = ""

    private var skill: StagedSkill? {
        stage.skills.first { $0.folderPath == selectedPath } ?? stage.skills.first
    }

    private var scope: SkillInstallScope {
        scopePath.isEmpty ? .user : .project(URL(filePath: scopePath, directoryHint: .isDirectory))
    }

    private var targets: [SkillInstallTarget] {
        library.targets(for: chosenAgents, scope: scope)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            if let skill {
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Space.xl) {
                        summary(skill)
                        contents(skill)
                        destination(skill)
                    }
                }
                .frame(maxHeight: 560)
                buttons(skill)
            }
        }
        .onAppear {
            selectedPath = stage.skills.first?.folderPath ?? ""
            chosenAgents = Set(library.agents.map(\.format))
            scopePath = project.map(SkillPaths.key) ?? ""
        }
    }

    private func summary(_ skill: StagedSkill) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Text("Review \(skill.name)")
                .settingsText(.title)
                .foregroundStyle(.dsTextPrimary)
            Text(
                [stage.source.displayText, stage.revision.map { "commit \($0.prefix(12))" }].compactMap(\.self)
                    .joined(separator: " · ")
            )
            .font(SettingsTextStyle.mono.font)
            .foregroundStyle(.dsTextTertiary)
            .textSelection(.enabled)
            if stage.skills.count > 1 {
                SettingsSelect(
                    label: "\(stage.skills.count) skills here", selection: $selectedPath,
                    options: stage.skills.map { .init(value: $0.folderPath, title: $0.name) }, width: 260)
            }
            if let description = skill.document?.frontmatter.description {
                Text(description)
                    .settingsText(.body)
                    .foregroundStyle(.dsTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(skill.folder.problems, id: \.self) { problem in
                Text(problem.message)
                    .settingsText(.caption)
                    .foregroundStyle(problem.severity == .error ? .dsDanger : .dsWarning)
            }
            if library.items.contains(where: { $0.key == SkillItem.key(for: skill.name) }) {
                Text("You already have a skill named \(skill.name); agents would find two.")
                    .settingsText(.caption)
                    .foregroundStyle(.dsWarning)
            }
        }
    }

    private func contents(_ skill: StagedSkill) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            if !skill.scripts.isEmpty {
                MCPNotice(
                    text:
                        "It includes \(skill.scripts.count) \(skill.scripts.count == 1 ? "script" : "scripts") an agent can run on your Mac. Read \(skill.scripts.count == 1 ? "it" : "them") before installing.",
                    tone: .warning)
            }
            Text("SKILL.md")
                .settingsText(.bodyMedium)
                .foregroundStyle(.dsTextPrimary)
            CappedHeightScrollView(maxHeight: 220) {
                Text(skill.files.first { $0.relativePath == "SKILL.md" }?.text ?? "")
                    .font(.dsMono)
                    .foregroundStyle(.dsTextSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DS.Space.md)
            }
            .background(.dsSurfaceSunken, in: .rect(cornerRadius: DS.Radius.card, style: .continuous))
            Text("Everything in it")
                .settingsText(.bodyMedium)
                .foregroundStyle(.dsTextPrimary)
            SkillFileList(files: skill.files)
        }
    }

    private func destination(_ skill: StagedSkill) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack {
                Text("Install for")
                    .settingsText(.bodyMedium)
                    .foregroundStyle(.dsTextPrimary)
                Spacer()
                SettingsSelect(label: "Install in", selection: $scopePath, options: scopeOptions, width: 220)
            }
            HStack(spacing: DS.Space.lg) {
                ForEach(library.agents) { agent in
                    Toggle(
                        agent.name,
                        isOn: Binding(
                            get: { chosenAgents.contains(agent.format) },
                            set: {
                                if $0 { chosenAgents.insert(agent.format) } else { chosenAgents.remove(agent.format) }
                            }
                        )
                    )
                    .skillsCheckbox()
                    .settingsText(.body)
                }
            }
            Text("Native writes")
                .settingsText(.caption)
                .foregroundStyle(.dsTextSecondary)
            ForEach(targets) { target in
                Text(
                    SkillPaths.abbreviated(target.directory + "/" + skill.installName, home: library.home) + "  ("
                        + library.agents.filter { target.agents.contains($0.format) }.map(\.name).joined(
                            separator: ", ")
                        + ")"
                )
                .font(SettingsTextStyle.mono.font)
                .foregroundStyle(.dsTextPrimary)
                .textSelection(.enabled)
            }
            if targets.isEmpty {
                Text("Choose at least one agent.")
                    .settingsText(.caption)
                    .foregroundStyle(.dsWarning)
            }
        }
    }

    private func buttons(_ skill: StagedSkill) -> some View {
        VStack(alignment: .trailing, spacing: DS.Space.md) {
            if let error {
                Text(error)
                    .settingsText(.body)
                    .foregroundStyle(.dsDanger)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: DS.Space.md) {
                Button("Back", action: onBack)
                    .buttonStyle(.ds(.ghost, size: .large))
                Spacer()
                if isInstalling { DotGridLoader(pattern: .settingUp) }
                Button("Cancel", action: onCancel)
                    .buttonStyle(.ds(.secondary, size: .large))
                    .keyboardShortcut(.cancelAction)
                Button("Install") {
                    let names = library.agents.filter { chosenAgents.contains($0.format) }.map(\.name)
                    onInstall(skill, targets, names.joined(separator: ", "))
                }
                .buttonStyle(.ds(.primary, size: .large))
                .keyboardShortcut(.defaultAction)
                .disabled(targets.isEmpty || isInstalling || skill.folder.problems.contains { $0.severity == .error })
            }
        }
    }

    private var scopeOptions: [SettingsSelect<String>.Option] {
        [SettingsSelect<String>.Option(value: "", title: "Every project (yours)")]
            + (library.host?.skillProjects ?? []).map {
                SettingsSelect<String>.Option(value: SkillPaths.key($0), title: $0.lastPathComponent)
            }
    }
}

extension View {
    /// A checkbox where the platform has one (the Mac); a switch elsewhere.
    fileprivate func skillsCheckbox() -> some View {
        #if os(macOS)
        toggleStyle(.checkbox)
        #else
        self
        #endif
    }
}
#endif
