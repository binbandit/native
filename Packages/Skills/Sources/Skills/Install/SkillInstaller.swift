import Exec
import Foundation

/// A folder a skill is installed into, and the agents that read it.
public struct SkillInstallTarget: Hashable, Sendable, Identifiable {
    public var id: String { directory }
    public var directory: String
    public var agents: Set<SkillAgentFormat>
}

/// A folder moved aside instead of deleted, so removing or updating a skill can be undone.
public struct SkillTrashEntry: Hashable, Sendable, Codable {
    public var originalPath: String
    public var trashedPath: String
}

/// How a skill was installed, kept by Native so it can be updated from the same place.
public struct SkillInstallRecord: Hashable, Sendable, Codable, Identifiable {
    public var id: UUID
    public var name: String
    public var source: SkillInstallSource
    public var revision: String?
    public var installedAt: Date
    public var paths: [String]

    public init(
        id: UUID = UUID(), name: String, source: SkillInstallSource, revision: String?, installedAt: Date,
        paths: [String]
    ) {
        self.id = id
        self.name = name
        self.source = source
        self.revision = revision
        self.installedAt = installedAt
        self.paths = paths
    }
}

/// Fetches, installs, updates and removes skills. Nothing is written until the caller has shown
/// the staged skill and the user confirmed; nothing is deleted, only moved to `trash`.
public struct SkillInstaller: Sendable {
    let files: any SkillFileSystem
    let stager: SkillStager
    let home: String
    let environment: [String: String]
    /// Native's own folder for skills moved aside, on the same machine.
    let trash: String

    public init(
        files: any SkillFileSystem, runner: any CommandRunner, registry: SkillsRegistry = SkillsRegistry(),
        home: String, environment: [String: String], trash: String
    ) {
        self.files = files
        self.stager = SkillStager(files: files, runner: runner, registry: registry, environment: environment)
        self.home = home
        self.environment = environment
        self.trash = trash
    }

    public func stage(_ source: SkillInstallSource) async throws(SkillInstallError) -> SkillStage {
        try await stager.stage(source)
    }

    /// Removes what `stage` fetched.
    public func discard(_ stage: SkillStage) {
        if let staging = stage.stagingPath { try? files.removeItem(atPath: staging) }
    }

    /// The fewest folders that reach every agent in `agents`: the shared `.claude/skills` and
    /// `.agents/skills` folders first, since several agents read each, then agents' own folders.
    public func targets(for agents: Set<SkillAgentFormat>, scope: SkillInstallScope) -> [SkillInstallTarget] {
        let project: URL? = if case .project(let url) = scope { url } else { nil }
        let base = project.map(SkillPaths.key) ?? home
        let shared = [
            SkillPaths.join(
                project == nil ? (environment["CLAUDE_CONFIG_DIR"] ?? SkillPaths.join(home, ".claude")) : SkillPaths.join(base, ".claude"),
                "skills"),
            SkillPaths.join(base, ".agents", "skills"),
        ]
        let own = SkillAgentFormat.allCases.filter(agents.contains).map {
            $0.installDirectory(for: scope, home: home, environment: environment)
        }
        var uncovered = agents
        var targets: [SkillInstallTarget] = []
        for directory in shared + own where !uncovered.isEmpty && !targets.contains(where: { $0.directory == directory }) {
            let readers = Set(agents.filter { $0.reads(directory, home: home, environment: environment, project: project) })
            guard !readers.isDisjoint(with: uncovered) else { continue }
            targets.append(SkillInstallTarget(directory: directory, agents: readers))
            uncovered.subtract(readers)
        }
        return targets
    }

    /// Copies `skill` into each target. Checks every destination first, so a clash writes nothing.
    public func install(_ skill: StagedSkill, into targets: [SkillInstallTarget]) throws(SkillInstallError) -> [String] {
        let destinations = targets.map { SkillPaths.join($0.directory, skill.installName) }
        let taken = destinations.filter(files.exists)
        guard taken.isEmpty else { throw .alreadyInstalled(taken) }
        var written: [String] = []
        do {
            for destination in destinations {
                try files.copyItem(atPath: skill.folderPath, toPath: destination)
                written.append(destination)
            }
        } catch {
            for path in written { try? files.removeItem(atPath: path) }
            throw .failed("Native couldn't write the skill: \(error.localizedDescription)")
        }
        return destinations
    }

    /// Replaces the skill at `path` with `skill`, keeping the old one in the trash for undo.
    public func replace(_ path: String, with skill: StagedSkill) throws(SkillInstallError) -> SkillTrashEntry {
        let entry = try moveToTrash(path)
        do {
            try files.copyItem(atPath: skill.folderPath, toPath: path)
        } catch {
            try? restore(entry)
            throw .failed("Native couldn't write the update, so it put the old version back: \(error.localizedDescription)")
        }
        return entry
    }

    /// Moves a skill folder (or the link to it) into Native's trash.
    public func moveToTrash(_ path: String) throws(SkillInstallError) -> SkillTrashEntry {
        guard files.exists(path) else { throw .missing(path) }
        let trashed = SkillPaths.join(trash, UUID().uuidString, URL(filePath: path).lastPathComponent)
        do {
            try files.moveItem(atPath: path, toPath: trashed)
        } catch {
            throw .failed("Native couldn't move \(path) aside: \(error.localizedDescription)")
        }
        return SkillTrashEntry(originalPath: path, trashedPath: trashed)
    }

    /// Puts a trashed folder back, replacing whatever an update put there.
    public func restore(_ entry: SkillTrashEntry) throws(SkillInstallError) {
        guard files.exists(entry.trashedPath) else { throw .missing(entry.trashedPath) }
        do {
            if files.exists(entry.originalPath) { try files.removeItem(atPath: entry.originalPath) }
            try files.moveItem(atPath: entry.trashedPath, toPath: entry.originalPath)
        } catch {
            throw .failed("Native couldn't put \(entry.originalPath) back: \(error.localizedDescription)")
        }
    }

    /// Removes a skill Native just installed, for undoing an install.
    public func uninstall(_ paths: [String]) {
        for path in paths { try? files.removeItem(atPath: path) }
    }

    /// What an update changes, file by file.
    public static func changes(from installed: [SkillFile], to staged: [SkillFile]) -> SkillUpdateChanges {
        let old = Dictionary(installed.map { ($0.relativePath, $0) }, uniquingKeysWith: { first, _ in first })
        let new = Dictionary(staged.map { ($0.relativePath, $0) }, uniquingKeysWith: { first, _ in first })
        return SkillUpdateChanges(
            added: new.keys.filter { old[$0] == nil }.sorted(),
            removed: old.keys.filter { new[$0] == nil }.sorted(),
            changed: new.keys.filter { key in
                old[key].map { $0.size != new[key]?.size || $0.text != new[key]?.text } ?? false
            }.sorted()
        )
    }
}

/// Files an update adds, removes and changes.
public struct SkillUpdateChanges: Hashable, Sendable {
    public var added: [String]
    public var removed: [String]
    public var changed: [String]

    public var isEmpty: Bool {
        added.isEmpty && removed.isEmpty && changed.isEmpty
    }
}
