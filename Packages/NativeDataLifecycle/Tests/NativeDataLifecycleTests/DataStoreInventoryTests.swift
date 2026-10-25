import Foundation
import Testing

@testable import NativeDataLifecycle

/// The inventory accounts for every store family, names code that exists, and is the one source
/// docs/enterprise/data-lifecycle.md is rendered from.
@Suite struct DataStoreInventoryTests {
    private static let root = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    private static let document = "docs/enterprise/data-lifecycle.md"
    private let inventory = DataStoreInventory.native

    @Test func everyStoreHasOneSoundEntry() {
        #expect(inventory.entries.map(\.id).sorted() == DataStoreID.allCases.sorted())
        #expect(inventory.problems == [])
    }

    /// The families the regulated-environments audit names, each with the stores that cover it.
    @Test func everyAuditedFamilyIsCovered() {
        let families: [String: [DataStoreID]] = [
            "host database, sidecars, recovery and queue": [.hostDatabase, .hostRuntime],
            "search and its read checkpoints": [.searchIndex],
            "session catalog, defaults and drafts": [.sessionCatalog, .sessionState, .drafts, .settings],
            "projects and repository trust": [.projects, .repositoryTrust],
            "automation and expeditions": [.automation, .expeditions, .expeditionDocuments],
            "attachments and task or pull request artifacts": [
                .attachments, .workingFiles, .pullRequestQuestions, .pullRequestClones,
            ],
            "git worktrees, refs, reflogs and checkpoints": [.taskWorktrees, .nativeRefs, .repositoryHistory],
            "plugin, skill, component, icon and celebration caches": [
                .plugins, .componentCaches, .skillsLibrary, .skillsInstalled, .skillsTrash, .agentIcons,
                .projectIcons, .celebrationAssets, .appUpdates,
            ],
            "Native-owned secrets and pairings": [
                .hostCredentials, .hostPairingIdentity, .orchestrationTokenSecret, .mcpSecrets, .hostPairings,
                .companionPairings,
            ],
            "diagnostics caches and logs": [.telemetrySentLog, .crashReportCache, .commandCoverage, .systemRecords],
            "approval audit": [.approvalAudit],
            "agent-owned histories": [.agentHistories, .agentConfiguration, .agentCredentials],
            "customer backups": [.customerBackups, .customerExports, .toolCredentials, .packageCaches],
            "remote host copies": [.remoteHostCopies],
        ]
        for (family, stores) in families {
            #expect(stores.allSatisfy { inventory.entry($0) != nil }, "\(family)")
        }
        let covered = Set(families.values.joined())
        let rest: Set<DataStoreID> = [.hostUpdates, .usage, .policyEnrollment, .mcpServers]
        #expect(covered.union(rest) == Set(DataStoreID.allCases))
    }

    @Test func ownershipIsLabeledApartAndAuditIsReservedAsUnknown() throws {
        let owners = Set(inventory.entries.map(\.ownership))
        #expect(owners == Set(DataOwnership.allCases))
        let audit = try #require(inventory.entry(.approvalAudit))
        guard case .unknown = audit.integration else {
            Issue.record("the approval audit's integration should stay unknown until it lands")
            return
        }
        #expect(audit.copies.map(\.location) == [.undetermined])
        // Only Native's own stores, and an agent's through an explicit adapter, wait for an adapter.
        for entry in inventory.entries where entry.support.delete == .adapterPending {
            #expect(entry.ownership == .native || entry.followUp == .externalAgents, "\(entry.id)")
        }
    }

    @Test func everyOwnerExistsInTheRepository() {
        for owner in Set(inventory.entries.flatMap(\.owners)) {
            #expect(FileManager.default.fileExists(atPath: Self.root.appending(path: owner).path), "\(owner)")
        }
    }

    @Test func pathTemplatesMatchOnlyTheirOwnPlaces() {
        let icons = DataLocation.file(.appSupport, ["AgentIcons", "registry-<hash>.json"])
        #expect(icons.contains(DataRelativePath(DataRoot(.appSupport), ["AgentIcons", "registry-0a1b.json"])))
        #expect(!icons.contains(DataRelativePath(DataRoot(.appSupport), ["AgentIcons", "registry-.json"])))
        #expect(!icons.contains(DataRelativePath(DataRoot(.appSupport), ["AgentIcons", "other.json"])))
        #expect(!icons.contains(DataRelativePath(DataRoot(.caches), ["AgentIcons", "registry-0a1b.json"])))
        let worktrees = DataLocation.file(.nativeHome, ["worktrees", "<repository>", "<task>"])
        #expect(worktrees.contains(DataRelativePath(DataRoot(.nativeHome), ["worktrees", "repo", "task", "file"])))
        #expect(!worktrees.contains(DataRelativePath(DataRoot(.nativeHome), ["worktrees", "repo"])))
        #expect(!worktrees.contains(DataRelativePath(DataRoot(.nativeHome), ["worktrees", "..", "task"])))
        let icon = DataLocation.file(.appSupport, ["ProjectIcons", "<kind>-<project>.<format>"])
        #expect(icon.contains(DataRelativePath(DataRoot(.appSupport), ["ProjectIcons", "custom-p1.png"])))
        #expect(!icon.contains(DataRelativePath(DataRoot(.appSupport), ["ProjectIcons", "custom.png"])))
    }

    /// The fixture plans an erasure across the whole inventory: every store in scope ends up either
    /// with outcomes or named as unaccounted, and with no adapters nothing is planned.
    @Test func aWholeInventoryErasureAccountsForEveryStore() throws {
        let manifest = try SyntheticWorkspace.Manifest.load()
        #expect(manifest.roots.allSatisfy { $0.path.hasPrefix(SyntheticWorkspace.base + "/") })
        #expect(manifest.approvedRoots.rejected.isEmpty)
        #expect(manifest.reports.count == manifest.stores.count)

        let request = try #require(
            DataLifecycleRequest(id: "erasure-all", purpose: .erasure([SyntheticWorkspace.alpha])))
        let planner = DataLifecyclePlanner(
            policy: SyntheticWorkspace.thirtyDays, holds: SyntheticWorkspace.noHolds, roots: manifest.approvedRoots)
        let plan = planner.plan(request, reports: manifest.reports, clock: SyntheticWorkspace.clock)

        let inScope = Set(inventory.entries.filter { $0.support.delete != .notApplicable }.map(\.id))
        let listed = Set(manifest.reports.keys)
        let unaccounted = Set(plan.unaccounted.map(\.store))
        #expect(listed.union(unaccounted) == inScope)
        #expect(listed.isDisjoint(with: unaccounted))
        #expect(plan.operations.isEmpty)
        #expect(plan.status == .blocked)
        #expect(plan.unaccounted.contains(DataUnaccountedStore(store: .customerBackups, reason: .ownedOutsideNative)))
        #expect(plan.unaccounted.contains(DataUnaccountedStore(store: .approvalAudit, reason: .integrationUnknown)))
        #expect(plan.outcomes(for: SyntheticWorkspace.alpha).allSatisfy { $0.disposition != .planned })
        let offline = plan.outcomes.first { $0.store == .remoteHostCopies }
        #expect(offline?.disposition == .unreachable)
    }

    @Test func theDocumentShowsTheInventoryAsTheCodeHasIt() throws {
        let url = Self.root.appending(path: Self.document)
        let text = try String(contentsOf: url, encoding: .utf8)
        let begin = "<!-- inventory:begin -->\n", end = "\n<!-- inventory:end -->"
        let start = try #require(text.range(of: begin), "\(Self.document) has no inventory markers")
        let stop = try #require(text.range(of: end, range: start.upperBound..<text.endIndex))
        let rendered = inventory.markdown
        if ProcessInfo.processInfo.environment["NATIVE_UPDATE_DOCS"] == "1" {
            try text.replacingCharacters(in: start.upperBound..<stop.lowerBound, with: rendered)
                .write(to: url, atomically: true, encoding: .utf8)
            return
        }
        #expect(
            String(text[start.upperBound..<stop.lowerBound]) == rendered,
            "Run NATIVE_UPDATE_DOCS=1 swift test --filter DataStoreInventoryTests in Packages/NativeDataLifecycle")
    }
}
