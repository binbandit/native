#if canImport(Skills)
import Foundation
import Skills

/// Installing, updating and removing skills. Each step that writes comes after the user has seen
/// what it writes, and returns what undoing it needs.
extension SkillLibrary {
    var installer: SkillInstaller {
        SkillInstaller(
            files: files, runner: runner, registry: registry, home: home, environment: environment, trash: trashFolder)
    }

    /// Fetches a source into a staging folder (or reads a local one) to show before installing.
    func stage(_ source: SkillInstallSource) async throws(SkillInstallError) -> SkillStage {
        await loadEnvironmentIfNeeded()
        return try await installer.stage(source)
    }

    func discard(_ stage: SkillStage) {
        installer.discard(stage)
    }

    func search(_ query: String) async throws(SkillsRegistryError) -> [RegistrySkill] {
        try await registry.search(query)
    }

    /// The folders a skill goes into so `agents` load it.
    func targets(for agents: Set<SkillAgentFormat>, scope: SkillInstallScope) -> [SkillInstallTarget] {
        installer.targets(for: agents, scope: scope)
    }

    /// Writes `skill` into `targets`, remembers where it came from, and reads again.
    func install(
        _ skill: StagedSkill, from stage: SkillStage, into targets: [SkillInstallTarget]
    ) async throws(SkillInstallError) -> SkillInstallRecord {
        let paths = try installer.install(skill, into: targets)
        let record = SkillInstallRecord(
            name: skill.name, source: source(of: skill, in: stage), revision: stage.revision, installedAt: .now,
            paths: paths)
        setRecords(records + [record])
        await read()
        return record
    }

    /// Takes an install back: removes what it wrote and forgets it.
    func undoInstall(_ record: SkillInstallRecord) async {
        installer.uninstall(record.paths)
        setRecords(records.filter { $0.id != record.id })
        await read()
    }

    /// How Native installed a skill, when it did.
    func record(for item: SkillItem) -> SkillInstallRecord? {
        records.last { record in
            SkillItem.key(for: record.name) == item.key && item.places.contains { record.paths.contains($0.path) }
        }
    }

    /// Fetches the latest version of a skill Native installed, with what would change.
    func stageUpdate(of item: SkillItem) async throws(SkillInstallError) -> SkillUpdatePlan {
        guard let record = record(for: item) else {
            throw .failed("Native didn't install \(item.name), so it doesn't know where to update it from.")
        }
        let stage = try await stage(record.source)
        guard let skill = stage.skills.first(where: { SkillItem.key(for: $0.name) == item.key }) ?? stage.skills.first
        else {
            discard(stage)
            throw .noSkills
        }
        let installed = SkillScanner(files: files).contents(of: record.paths[0])
        return SkillUpdatePlan(
            record: record, stage: stage, skill: skill,
            changes: SkillInstaller.changes(from: installed, to: skill.files))
    }

    /// Replaces every installed copy with the staged version; the old ones go to the trash.
    func applyUpdate(_ plan: SkillUpdatePlan) async throws(SkillInstallError) -> [SkillTrashEntry] {
        var entries: [SkillTrashEntry] = []
        do {
            for path in plan.record.paths where files.itemKind(atPath: path) != nil {
                entries.append(try installer.replace(path, with: plan.skill))
            }
        } catch {
            for entry in entries { try? installer.restore(entry) }
            discard(plan.stage)
            throw error
        }
        var updated = plan.record
        updated.revision = plan.stage.revision
        updated.installedAt = .now
        setRecords(records.map { $0.id == updated.id ? updated : $0 })
        discard(plan.stage)
        await read()
        return entries
    }

    /// Moves skill folders (or links to them) to Native's trash. Never deletes.
    func remove(_ paths: [String]) async throws(SkillInstallError) -> [SkillTrashEntry] {
        var entries: [SkillTrashEntry] = []
        do {
            for path in paths { entries.append(try installer.moveToTrash(path)) }
        } catch {
            for entry in entries { try? installer.restore(entry) }
            throw error
        }
        await read()
        return entries
    }

    /// Puts trashed folders back, undoing a removal or an update.
    func restore(_ entries: [SkillTrashEntry]) async {
        do {
            for entry in entries { try installer.restore(entry) }
        } catch {
            problem = error.localizedDescription
        }
        await read()
    }

    /// The source to update a staged skill from: for a repository of several skills, its folder.
    private func source(of skill: StagedSkill, in stage: SkillStage) -> SkillInstallSource {
        switch stage.source {
        case .git(let url, let ref, let subpath) where !skill.relativePath.isEmpty:
            let folder = [subpath, skill.relativePath].compactMap(\.self).joined(separator: "/")
            return .git(url: url, ref: ref, subpath: folder)
        case .folder where !skill.relativePath.isEmpty:
            return .folder(path: skill.folderPath)
        default:
            return stage.source
        }
    }
}

/// An update fetched and compared, waiting for the user to confirm.
struct SkillUpdatePlan: Identifiable {
    var id: UUID { record.id }
    let record: SkillInstallRecord
    let stage: SkillStage
    let skill: StagedSkill
    let changes: SkillUpdateChanges
}
#endif
