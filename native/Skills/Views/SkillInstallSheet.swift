#if canImport(Skills)
import Skills
import SwiftUI
import UniformTypeIdentifiers

/// Installing a skill: pick where it comes from, see everything in it (its SKILL.md and every
/// script, since skills can run code), choose the agents and the scope, then write. Nothing is
/// written before the user presses Install.
struct SkillInstallSheet: View {
    let library: SkillLibrary
    let project: URL?
    let onInstalled: (SkillInstallRecord, String) -> Void

    private enum Phase {
        case choosing
        case fetching(SkillInstallSource)
        case reviewing(SkillStage)
        case installing(SkillStage)
        case failed(SkillInstallSource, String)
    }

    @Environment(\.dismiss) private var dismiss
    @State private var phase = Phase.choosing
    @State private var input = ""
    @State private var query = ""
    @State private var results: [RegistrySkill] = []
    @State private var searchMessage: String?
    @State private var isSearching = false
    @State private var isPickingFolder = false
    /// Why the last install failed, shown in the review so the user can change something.
    @State private var installError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            switch phase {
            case .choosing:
                choosing
            case .fetching(let source):
                header("Fetching…", "Getting \(source.displayText) to show you before anything is installed.")
                DotGridLoader(pattern: .settingUp)
                footer { cancelButton }
            case .reviewing(let stage), .installing(let stage):
                SkillInstallReview(
                    library: library, stage: stage, project: project, isInstalling: isInstalling, error: installError,
                    onBack: { back(from: stage) }, onCancel: { cancel(stage) },
                    onInstall: { skill, targets, agents in install(skill, from: stage, into: targets, agents: agents) })
            case .failed(let source, let message):
                header("It couldn't be fetched", message)
                footer {
                    Button("Back") { phase = .choosing }
                        .buttonStyle(.ds(.secondary, size: .large))
                    Button("Try Again") { fetch(source) }
                        .buttonStyle(.ds(.primary, size: .large))
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(DS.Space.xxl)
        .frame(width: 640)
        .background(.dsBackground)
        .fileImporter(isPresented: $isPickingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { fetch(.folder(path: url.path(percentEncoded: false))) }
        }
    }

    private var isInstalling: Bool {
        if case .installing = phase { true } else { false }
    }

    // MARK: - Choosing

    private var choosing: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            header(
                "Install a Skill",
                "Skills can run code on your Mac, so Native shows you everything in one before writing any of it.")
            VStack(alignment: .leading, spacing: DS.Space.md) {
                Text("From a repository or a folder")
                    .settingsText(.bodyMedium)
                    .foregroundStyle(.dsTextPrimary)
                HStack(spacing: DS.Space.md) {
                    TextField(
                        "Source", text: $input, prompt: Text("owner/repo, a git or skills.sh URL, or a folder path")
                    )
                    .font(.dsMono)
                    .mcpFieldStyle()
                    .onSubmit(fetchInput)
                    Button("Fetch", action: fetchInput)
                        .buttonStyle(.ds(.secondary, size: .medium))
                        .disabled(SkillInstallSource.parse(input, home: library.home) == nil)
                    Button("Choose Folder…") { isPickingFolder = true }
                        .buttonStyle(.ds(.ghost, size: .medium))
                }
                if !input.isEmpty, SkillInstallSource.parse(input, home: library.home) == nil {
                    caption("That isn't a git URL, owner/repo, skills.sh link or folder path.", color: .dsWarning)
                }
            }
            VStack(alignment: .leading, spacing: DS.Space.md) {
                Text("Or search skills.sh")
                    .settingsText(.bodyMedium)
                    .foregroundStyle(.dsTextPrimary)
                HStack(spacing: DS.Space.md) {
                    TextField("Search", text: $query, prompt: Text("pdf, swiftui, code review…"))
                        .mcpFieldStyle()
                        .onSubmit(search)
                    Button("Search", action: search)
                        .buttonStyle(.ds(.secondary, size: .medium))
                        .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
                }
                caption(
                    "skills.sh is an open index of skills in public GitHub repositories, ranked by installs. Anyone can publish one; review before installing.",
                    color: .dsTextTertiary)
                if isSearching {
                    DotGridLoader(pattern: .waiting)
                } else if let searchMessage {
                    caption(searchMessage, color: .dsTextSecondary)
                }
                if !results.isEmpty {
                    CappedHeightScrollView(maxHeight: 260) {
                        SettingsRowGroup {
                            ForEach(results) { skill in
                                SettingsRow(
                                    skill.name,
                                    description: Text(skill.source),
                                    detail: skill.installs.map {
                                        Text("\($0.formatted(.number.notation(.compactName))) installs")
                                    }
                                ) {
                                    Button("Review") { fetch(skill.installSource) }
                                        .buttonStyle(.ds(.secondary, size: .medium))
                                }
                            }
                        }
                        .padding(.vertical, DS.Space.xs)
                    }
                }
            }
            footer { cancelButton }
        }
    }

    // MARK: - Pieces

    private func header(_ title: String, _ message: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Text(title)
                .settingsText(.title)
                .foregroundStyle(.dsTextPrimary)
            Text(message)
                .settingsText(.body)
                .foregroundStyle(.dsTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private func caption(_ text: String, color: Color) -> some View {
        Text(text)
            .settingsText(.caption)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func footer<Buttons: View>(@ViewBuilder _ buttons: () -> Buttons) -> some View {
        HStack(spacing: DS.Space.md) {
            Spacer()
            buttons()
        }
    }

    private var cancelButton: some View {
        Button("Cancel") { dismiss() }
            .buttonStyle(.ds(.secondary, size: .large))
            .keyboardShortcut(.cancelAction)
    }

    // MARK: - Actions

    private func fetchInput() {
        guard let source = SkillInstallSource.parse(input, home: library.home) else { return }
        fetch(source)
    }

    private func fetch(_ source: SkillInstallSource) {
        phase = .fetching(source)
        Task {
            do {
                phase = .reviewing(try await library.stage(source))
            } catch {
                phase = .failed(source, error.localizedDescription)
            }
        }
    }

    private func search() {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        isSearching = true
        searchMessage = nil
        Task {
            defer { isSearching = false }
            do {
                results = try await library.search(text)
                searchMessage = results.isEmpty ? "Nothing on skills.sh matches \"\(text)\"." : nil
            } catch {
                results = []
                searchMessage = error.localizedDescription
            }
        }
    }

    private func back(from stage: SkillStage) {
        library.discard(stage)
        installError = nil
        phase = .choosing
    }

    private func cancel(_ stage: SkillStage) {
        library.discard(stage)
        dismiss()
    }

    private func install(
        _ skill: StagedSkill, from stage: SkillStage, into targets: [SkillInstallTarget], agents: String
    ) {
        phase = .installing(stage)
        installError = nil
        Task {
            do {
                let record = try await library.install(skill, from: stage, into: targets)
                library.discard(stage)
                onInstalled(record, agents)
                dismiss()
            } catch {
                phase = .reviewing(stage)
                installError = error.localizedDescription
            }
        }
    }
}
#endif
