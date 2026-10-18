#if canImport(Skills)
import Exec
import Foundation
import Observation
import Skills
import os

/// Every skill the user's agents load, wherever it lives, one switch per skill, and installing,
/// updating and removing them. Views, the plugin and other clients go through this model, never
/// to the files directly.
///
/// Switches never edit a skill or an agent's settings: they become a `SessionPolicy`, which each
/// agent's plugin turns into its own mechanism (Claude Code per session, Codex at launch). Files
/// change only when the user installs, updates or removes a skill, after seeing exactly what.
@Observable
final class SkillLibrary {
    /// Every skill found, by name.
    private(set) var items: [SkillItem] = []
    /// The folders read, with the agents that read each.
    private(set) var roots: [SkillRoot] = []
    private(set) var isReading = false
    private(set) var lastRead: Date?
    private(set) var switches: SkillSwitches
    /// How Native installed skills, so it can update them from the same place.
    private(set) var records: [SkillInstallRecord]
    /// Something that went wrong, shown on the page until dismissed.
    var problem: String?

    /// The app, once `SkillsPlugin.connect` has run.
    @ObservationIgnored var host: (any SkillLibraryHost)?
    @ObservationIgnored let files: any SkillFileSystem
    @ObservationIgnored let runner: any CommandRunner
    @ObservationIgnored let registry: SkillsRegistry
    @ObservationIgnored private let supportFolder: URL
    @ObservationIgnored private(set) var environment: [String: String] = [:]
    @ObservationIgnored let logger = Logger(subsystem: "Native", category: "Skills")

    init(
        files: any SkillFileSystem = LocalSkillFiles(),
        runner: any CommandRunner = SkillLibrary.defaultRunner,
        registry: SkillsRegistry = SkillsRegistry(),
        supportFolder: URL = SkillLibrary.defaultSupportFolder
    ) {
        self.files = files
        self.runner = runner
        self.registry = registry
        self.supportFolder = supportFolder
        let stored = Self.load(from: supportFolder.appending(path: "skills.json"))
        switches = stored.store?.switches ?? SkillSwitches()
        records = stored.store?.records ?? []
        problem = stored.problem
    }

    /// This Mac's processes; elsewhere git runs on a host, which isn't connected here yet.
    static var defaultRunner: any CommandRunner {
        #if os(macOS)
        LocalCommandRunner()
        #else
        SkillsHostlessRunner()
        #endif
    }

    /// Application Support, per bundle id like the other stores, so dev instances keep their own.
    static var defaultSupportFolder: URL {
        URL.applicationSupportDirectory.appending(
            path: Bundle.main.bundleIdentifier ?? "Native", directoryHint: .isDirectory)
    }

    var home: String {
        environment["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
    }

    var agents: [SkillsAgent] {
        host?.skillAgents ?? []
    }

    /// Native's own skills, as of the last read.
    private(set) var nativeSkills: [NativeSkillListing] = []

    // MARK: - Reading

    /// Reads every skills folder of every agent again, off the main thread. Runs at connect, when
    /// the app becomes active, after every change, and on demand; nothing reads files in `body`.
    func read() async {
        guard !isReading, let host else { return }
        isReading = true
        defer { isReading = false }
        environment = await host.skillEnvironment()
        let (roots, items) = await Task.detached {
            [files, home, environment, formats = Set(agents.map(\.format)), projects = host.skillProjects] in
            Self.scan(files: files, formats: formats, home: home, environment: environment, projects: projects)
        }.value
        apply(roots: roots, items: items)
    }

    /// The first read, on the main thread: agents that apply switches at launch start right after
    /// connect and need the inventory already. Only lists folders and reads SKILL.md files.
    func readAtStartup() {
        guard let host else { return }
        let (roots, items) = Self.scan(
            files: files, formats: Set(agents.map(\.format)), home: home, environment: environment,
            projects: host.skillProjects)
        apply(roots: roots, items: items)
    }

    /// Reads again unless the last read is recent, for when the app comes back to the front.
    func readIfStale() async {
        guard lastRead.map({ Date.now.timeIntervalSince($0) > 10 }) ?? true else { return }
        await read()
    }

    /// The host's environment, read once before a first install if no read has happened yet.
    func loadEnvironmentIfNeeded() async {
        if environment.isEmpty, let host { environment = await host.skillEnvironment() }
    }

    private nonisolated static func scan(
        files: any SkillFileSystem, formats: Set<SkillAgentFormat>, home: String, environment: [String: String],
        projects: [URL]
    ) -> ([SkillRoot], [SkillItem]) {
        let roots = SkillAgentFormat.roots(
            for: formats, home: home, environment: environment, projects: projects, files: files)
        return (roots, SkillInventory.items(SkillScanner(files: files).scan(roots)))
    }

    private func apply(roots: [SkillRoot], items: [SkillItem]) {
        let native = host?.nativeSkills ?? []
        if nativeSkills != native { nativeSkills = native }
        if self.roots != roots { self.roots = roots }
        if self.items != items { self.items = items }
        lastRead = .now
    }

    func item(_ key: String) -> SkillItem? {
        items.first { $0.key == key }
    }

    // MARK: - Switches

    func mode(of key: String, in project: URL?) -> SkillSwitches.Mode {
        switches.mode(of: key, in: project)
    }

    /// Sets a switch (nil follows the global one) and returns the previous one, for undo. Agents
    /// that apply switches at launch restart once idle.
    @discardableResult
    func setMode(_ mode: SkillSwitches.Mode?, for key: String, in project: URL?) -> SkillSwitches.Mode? {
        let previous = switches.explicitMode(of: key, in: project)
        switches.set(mode, for: key, in: project)
        persist()
        Task { await host?.skillApplyLaunchPolicies(force: false) }
        return previous
    }

    /// Why a switch doesn't fully reach some running agent, for the row.
    func limitations(of item: SkillItem) -> [String] {
        let support = Dictionary(agents.map { ($0.format, $0.switching) }, uniquingKeysWith: { first, _ in first })
        return switches.limitations(of: item, agents: support)
    }

    /// Whether Native's own skill `id` is on for a session in `directory`.
    func isNativeSkillEnabled(_ id: String, in directory: URL?) -> Bool {
        switches.mode(of: SkillItem.key(for: id), in: directory) == .on
    }

    // MARK: - Policy

    /// The skills off for a session, by name, for agents that apply switches per session.
    /// Native's own skills that are off are in it too, by id, so the tools that serve them can
    /// leave them out for that session.
    func sessionPolicy(for session: SessionContext) -> SessionPolicy {
        let off =
            switches.offList(for: items, in: session.cwd).names
            + nativeSkills.map(\.id).filter { !isNativeSkillEnabled($0, in: session.cwd) }
        let everywhere = Set(
            (items.map(\.name) + nativeSkills.map(\.id)).filter {
                switches.mode(of: SkillItem.key(for: $0), in: nil) == .off
            })
        return SessionPolicy(
            disabledSkills: off.map {
                SessionPolicy.DisabledSkill(
                    name: $0, path: nil, scope: everywhere.contains($0) ? .allProjects : .session)
            })
    }

    /// The skills off for every session of `agent`, by file, for agents that apply switches at
    /// launch. Only files that agent reads, so another agent's skill never restarts it.
    func launchPolicy(for agent: AgentDefinition.ID) -> SessionPolicy {
        guard let format = agents.first(where: { $0.id == agent })?.format else { return .none }
        let reachable = items.compactMap { item -> SkillItem? in
            var item = item
            item.places = item.places.filter { $0.root.agents.contains(format) }
            return item.places.isEmpty ? nil : item
        }
        return SessionPolicy(
            disabledSkills: switches.processOffList(for: reachable).skillFiles.map {
                SessionPolicy.DisabledSkill(name: nil, path: $0, scope: .allProjects)
            })
    }

    // MARK: - Persistence

    private struct Store: Codable {
        var switches: SkillSwitches
        var records: [SkillInstallRecord]
    }

    /// One small JSON file in Application Support, rewritten on every change.
    func persist() {
        let url = supportFolder.appending(path: "skills.json")
        do {
            try FileManager.default.createDirectory(at: supportFolder, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(Store(switches: switches, records: records)).write(to: url, options: .atomic)
        } catch {
            problem = "Couldn't save your skill switches: \(error.localizedDescription)"
        }
    }

    private static func load(from url: URL) -> (store: Store?, problem: String?) {
        guard let data = try? Data(contentsOf: url) else { return (nil, nil) }
        do {
            return (try JSONDecoder().decode(Store.self, from: data), nil)
        } catch {
            return (nil, "Native couldn't read its saved skill switches, so every skill starts on.")
        }
    }

    func setRecords(_ records: [SkillInstallRecord]) {
        self.records = records
        persist()
    }

    /// Native's folder for skills moved aside, so removing and updating can be undone.
    var trashFolder: String {
        supportFolder.appending(path: "Skills Trash").path(percentEncoded: false)
    }
}

/// Where there's no local process to run (iPadOS without a host), git can't run.
private struct SkillsHostlessRunner: CommandRunner {
    func run(_ command: Command) async throws -> CommandResult {
        throw CommandError.unavailable("Installing from git needs Native on a Mac, or a connected host.")
    }
}
#endif
