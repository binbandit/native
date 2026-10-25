import Foundation
import Testing

@testable import NativePolicy

/// Every key and capability is accounted for in code, in the sample profile and in the coverage
/// matrix, so adding one without deciding how it's enforced fails here.
@Suite struct PolicyCoverageTests {
    private static let root = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    private func document(_ path: String) throws -> String {
        try String(contentsOf: Self.root.appending(path: path), encoding: .utf8)
    }

    /// Rows of the matrix's tables, by their first cell's backticked id.
    private func matrixRows() throws -> [String: [String]] {
        var rows: [String: [String]] = [:]
        for line in try document("docs/enterprise/policy-coverage.md").split(separator: "\n")
        where line.hasPrefix("| `") {
            let cells = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            rows[cells[0].trimmingCharacters(in: CharacterSet(charactersIn: "`"))] = cells
        }
        return rows
    }

    @Test func everyNetworkServiceBelongsToACapability() {
        let covered = Set(PolicyCapability.allCases.flatMap(\.coverage.services))
        #expect(covered == Set(NativePolicy.NetworkService.allCases))
    }

    @Test func everyKeyHasARoleAndCapabilityOrSaysWhyNot() {
        let displayOnly: Set<PolicyKey> = [
            .organizationName, .organizationContact, .appearanceCodeTheme, .appearanceCodeThemeReason,
            .shortcutBindings,
        ]
        for key in PolicyKey.allCases {
            #expect(key.role == .deployment || !key.capabilities.isEmpty || displayOnly.contains(key), "\(key)")
            #expect(!key.owners.isEmpty, "\(key)")
        }
        for capability in PolicyCapability.allCases {
            #expect(!capability.coverage.owners.isEmpty, "\(capability)")
        }
    }

    @Test func everyOwnerExistsInTheRepository() {
        let owners = Set(PolicyCapability.allCases.flatMap(\.coverage.owners) + PolicyKey.allCases.flatMap(\.owners))
        for owner in owners {
            #expect(FileManager.default.fileExists(atPath: Self.root.appending(path: owner).path), "\(owner)")
        }
    }

    @Test func coverageMatrixListsEveryKeyAndCapabilityAsTheCodeDoes() throws {
        let rows = try matrixRows()
        for key in PolicyKey.allCases {
            let row = try #require(rows[key.rawValue], "\(key.rawValue) is missing from policy-coverage.md")
            #expect(row[1] == key.role.rawValue, "\(key.rawValue)")
        }
        for capability in PolicyCapability.allCases {
            let row = try #require(
                rows[capability.rawValue], "\(capability.rawValue) is missing from policy-coverage.md")
            #expect(row[1] == capability.coverage.kind.rawValue, "\(capability.rawValue)")
            #expect(row.last == capability.coverage.enforcement.rawValue, "\(capability.rawValue)")
        }
        let known = Set(PolicyKey.allCases.map(\.rawValue) + PolicyCapability.allCases.map(\.rawValue))
        #expect(Set(rows.keys).subtracting(known).isEmpty, "rows for ids the code doesn't have")
    }

    @Test func enterpriseGuideAndSampleProfileNameEveryKey() throws {
        let guide = try document("docs/enterprise.md")
        let profile = try document("docs/enterprise/native-policy.mobileconfig")
        for key in PolicyKey.allCases {
            #expect(guide.contains("`\(key.rawValue)`"), "\(key.rawValue) is missing from enterprise.md")
            #expect(profile.contains("<key>\(key.rawValue)</key>"), "\(key.rawValue) is missing from the sample")
        }
    }

    @Test func inspectionCoversEveryKeyAndCapabilityOnce() {
        for policy in [PolicyLoader.load(from: StaticPolicySource()), sampleUnderRestrictedMode()] {
            let inspection = policy.inspection
            #expect(inspection.keys.map(\.key) == PolicyKey.allCases)
            #expect(inspection.capabilities.map(\.capability) == PolicyCapability.allCases)
        }
    }

    /// Restricted mode can't be talked into an unconverted capability, however permissive the
    /// organization's values are.
    @Test func restrictedModeKeepsUnconvertedCapabilitiesOff() {
        let inspection = sampleUnderRestrictedMode().inspection
        for entry in inspection.capabilities where entry.capability != .audit {
            #expect(entry.decision.isPermitted == (entry.enforcement == .converted), "\(entry.capability)")
        }
    }

    /// Every key managed with its most permissive valid value, every service enabled, internal-only.
    private func sampleUnderRestrictedMode() -> NativePolicy {
        let origins = ["https://internal.example"]
        let services = Dictionary(
            uniqueKeysWithValues: NativePolicy.NetworkService.allCases.map {
                ($0.rawValue, ["enabled": true, "origins": origins] as [String: Any])
            })
        return PolicyLoader.load(
            from: StaticPolicySource(managed: [
                "policy.deployment.mode": "internalOnly",
                "policy.network": ["localIPC": true, "services": services],
                "policy.approvals.knowledge": #"{"version":1,"programs":[],"locations":[]}"#,
                "policy.approvals.countUnknownPrograms": true,
                "policy.agents.allowed": ["codex"], "policy.agents.environment": ["codex": ["A": "1"]],
                "policy.mcp.allowed": ["*"], "policy.mcp.blocked": [String](), "policy.mcp.required": [[String: Any]](),
                "policy.plugins.allowed": ["acme"], "policy.celebrations.downloadsEnabled": true,
                "policy.celebrations.baseURL": "https://internal.example/art/", "policy.catalog.enabled": true,
                "policy.catalog.indexURL": "https://internal.example/index.json", "policy.skills.blocked": [String](),
                "policy.permissions.forbiddenModes": [String](), "policy.scripts.enabled": true,
                "policy.git.worktreeFetch": true, "policy.taskScripts.userScripts": true,
                "policy.taskScripts.repositoryScripts": true, "policy.celebrations.enabled": true,
                "policy.organization.name": "Example", "policy.labs.enabled": true, "policy.companion.enabled": true,
                "policy.remoteHosts.enabled": true, "policy.updates.feedURL": "https://internal.example/appcast.xml",
                "policy.updates.enabled": true, "policy.updates.channels": ["stable"],
                "policy.search.retentionDays": 30, "policy.shortcuts.bindings": [String: String](),
                "policy.ai.instructions": [String: String](), "policy.telemetry.native": "user",
                "policy.telemetry.endpoints": [["url": "https://internal.example/otel"]],
            ]))
    }
}
