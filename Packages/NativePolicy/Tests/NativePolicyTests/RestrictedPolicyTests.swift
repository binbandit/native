import Foundation
import Testing

@testable import NativePolicy

@Suite struct RestrictedPolicyTests {
    private func load(
        managed: [String: Any] = [:], user: [String: Any] = [:], status: ManagedSourceStatus = .available,
        enrollment: (any PolicyEnrollmentStore)? = nil
    ) -> NativePolicy {
        PolicyLoader.load(
            from: StaticPolicySource(managed: managed, user: user, status: status, enrollment: enrollment))
    }

    /// The organization's internal-only mode, with `extra` managed keys.
    private func internalOnly(_ extra: [String: Any] = [:]) -> [String: Any] {
        extra.merging(["policy.deployment.mode": "internalOnly"]) { $1 }
    }

    @Test func ordinaryDefaultsAllowEveryCapabilityAndPlugin() {
        let policy = load()
        #expect(policy == .default)
        #expect(policy.deployment.state == .absent && policy.deployment.revision == nil)
        for capability in PolicyCapability.allCases {
            let decision = policy.decision(for: capability)
            switch capability {
            case .audit: #expect(decision.state == .required)
            // Nothing to send to until the organization names a collector.
            case .organizationDiagnostics, .auditExport:
                #expect(decision == .disabled(.notConfigured(.telemetryEndpoints)))
            default: #expect(decision == .allowed, "\(capability)")
            }
        }
        for origin in [PluginAdmission.Origin.builtIn, .installed, .system] {
            #expect(policy.admission(ofPlugin: "any", origin: origin, capabilities: nil).isAdmitted)
        }
    }

    @Test func theUsersOwnBadValuesNeverTakeAnythingAwayWithoutAProfile() {
        let store = MemoryPolicyEnrollmentStore()
        let policy = load(
            user: [
                "policy.network": "everything", "policy.scripts.enabled": "true", "policy.agents.environment": 42,
                "policy.mcp.blocked": "github", "policy.updates.channels": "stable",
            ],
            enrollment: store)
        #expect(!policy.isRestricted && policy.deployment.state == .absent && policy.deployment.lockdown == nil)
        #expect(policy.scriptsEnabled && policy.agents.allowed == nil && policy.mcp.allowed == nil)
        #expect(policy.updates.isEnabled && policy.keyStatus.values.allSatisfy { !$0.validity.isFailure })
        // Native's own connections still refuse the unusable network setting; agents and servers run.
        #expect(!policy.network.isValid)
        #expect(policy.decision(for: .agentExecution) == .allowed)
        #expect(policy.decision(for: .mcpExecution) == .allowed)
        #expect(policy.admission(ofPlugin: "any", origin: .builtIn, capabilities: nil).isAdmitted)
        #expect(store.load() == nil)
        // The same setting from the organization denies what depends on it.
        let managed = load(managed: ["policy.network": "everything"])
        #expect(managed.decision(for: .agentExecution) == .disabled(.invalidValue(.network)))
    }

    @Test func wrongManagedTypesNeverFallBackToUserOrDefault() throws {
        let cases: [(String, Any)] = [
            ("policy.scripts.enabled", "true"), ("policy.scripts.enabled", 1), ("policy.scripts.enabled", ["true"]),
            ("policy.labs.enabled", Date()), ("policy.telemetry.native", "always"), ("policy.agents.allowed", "codex"),
            ("policy.mcp.required", ["name": "docs"]), ("policy.plugins.allowed", ["ids": ["acme"]]),
            ("policy.search.retentionDays", 1.5), ("policy.updates.feedURL", "updates.example.com/appcast.xml"),
        ]
        for (key, value) in cases {
            try expectFailsClosed(key: key, value: value)
        }
    }

    private func expectFailsClosed(key: String, value: Any) throws {
        let policyKey = try #require(PolicyKey(rawValue: key))
        for mode in ["ordinary", "internalOnly"] {
            var user: [String: Any] = [
                "policy.agents.allowed": ["codex"], "policy.plugins.allowed": ["acme"], "policy.telemetry.native": "on",
            ]
            user[key] = user[key] ?? true
            let policy = load(managed: ["policy.deployment.mode": mode, key: value], user: user)
            #expect(policy.keyStatus[policyKey] == PolicyKeyStatus(validity: .invalid, origin: .failClosed))
            #expect(policy.isManaged(policyKey))
            #expect(policy.deployment.state == .invalid)
            #expect(!policy.scriptsEnabled || policyKey != .scriptsEnabled)
            #expect(!policy.labsEnabled || policyKey != .labsEnabled)
            #expect(policy.telemetry.native == .off || policyKey != .telemetryNative)
            #expect(policy.agents.allowed == [] || ![.agentsAllowed, .mcpRequired].contains(policyKey))
            #expect(policy.allowedPlugins == [] || policyKey != .pluginsAllowed)
            #expect(policy.searchRetentionDays == 1 || policyKey != .searchRetentionDays)
            #expect(!policy.updates.isEnabled || policyKey != .updatesFeedURL)
            for capability in policyKey.capabilities {
                #expect(policy.decision(for: capability) == .disabled(.invalidValue(policyKey)), "\(capability)")
            }
        }
    }

    @Test func mixedArraysKeepTheUsablePartOnlyInOrdinaryMode() {
        let mixed: [String: Any] = ["policy.plugins.allowed": ["acme", 3, ""]]
        let ordinary = load(managed: mixed)
        #expect(ordinary.allowedPlugins == ["acme"])
        #expect(
            ordinary.diagnostics.map(\.problem) == [
                "item 2 isn't a non-empty string; skipped", "item 3 isn't a non-empty string; skipped",
            ])
        #expect(ordinary.admission(ofPlugin: "acme", origin: .installed, capabilities: nil).isAdmitted)

        let restricted = load(managed: internalOnly(mixed))
        #expect(restricted.allowedPlugins == [])
        #expect(restricted.keyStatus[.pluginsAllowed]?.validity == .invalid)
        #expect(restricted.diagnostics.map(\.problem) == ["has 2 unusable entries; denied"])
        #expect(
            restricted.admission(ofPlugin: "acme", origin: .installed, capabilities: [.pluginAppearance])
                == PluginAdmission(reason: .notAllowed))
    }

    @Test func requiredServerAndCollectorFieldsMustHaveTheirTypes() {
        let policy = load(managed: [
            "policy.mcp.required": [
                ["name": "docs", "url": "https://mcp.example.com", "headers": "Bearer token"],
                ["name": "lint", "command": "lintd", "args": "--stdio"],
                ["name": "ok", "command": "okd"],
            ],
            "policy.telemetry.endpoints": [["url": "https://otel.example.com", "headers": ["x-key": 3]]],
        ])
        #expect(policy.mcp.required.map(\.name) == ["ok"])
        #expect(policy.telemetry.endpoints.isEmpty)
        #expect(policy.diagnostics.count == 3)
    }

    @Test func invalidSecurityValuesDenyWhatTheyShape() {
        for key in ["policy.agents.environment", "policy.permissions.forbiddenModes", "policy.skills.blocked"] {
            let policy = load(managed: [key: 42, "policy.agents.allowed": ["codex"]])
            #expect(policy.agents.allowed == [], "\(key)")
            #expect(policy.decision(for: .agentExecution).state == .disabled)
        }
        let blocked = load(managed: ["policy.mcp.blocked": "github"])
        #expect(blocked.mcp.allowed == [] && !blocked.mcp.allows(name: "anything"))
        let channels = load(managed: ["policy.updates.channels": "stable"])
        #expect(!channels.updates.isEnabled)
        let mirror = load(managed: ["policy.celebrations.baseURL": "ftp://mirror.example.com"])
        #expect(!mirror.celebrations.downloadsEnabled)
    }

    @Test func unknownModesAndKeysLockRestrictedPolicyDown() {
        for mode: Any in ["airgap", "", 1, ["internalOnly"]] {
            let policy = load(
                managed: ["policy.deployment.mode": mode, "policy.plugins.allowed": ["acme"]],
                user: ["policy.deployment.mode": "ordinary"])
            #expect(policy.deployment.lockdown == .invalidMode)
            #expect(policy.deploymentMode == .airGapped && policy.deployment.state == .invalid)
            #expect(policy.allowedPlugins == [])
            #expect(policy.decision(for: .iconDownload) == .disabled(.policyUnavailable))
        }
        let typo = load(managed: internalOnly(["policy.scripts.enable": true]))
        #expect(typo.deployment.lockdown == .unknownKeys)
        #expect(typo.decision(for: .pluginActivation) == .disabled(.unknownPolicyKey))
        #expect(
            typo.admission(ofPlugin: "x", origin: .builtIn, capabilities: [])
                == PluginAdmission(reason: .unknownPolicyKey))
        // Ordinary mode only reports the typo.
        let ordinaryTypo = load(managed: ["policy.scripts.enable": false])
        #expect(ordinaryTypo.deployment.lockdown == nil && ordinaryTypo.scriptsEnabled)
        #expect(ordinaryTypo.diagnostics.map(\.key) == ["policy.scripts.enable"])
    }

    @Test(arguments: [ManagedSourceStatus.unavailable, .malformed])
    func unreadableSourcesDenyEverythingOptional(status: ManagedSourceStatus) {
        let policy = load(
            managed: ["policy.plugins.allowed": ["acme"], "policy.scripts.enabled": true],
            user: ["policy.labs.enabled": true],
            status: status)
        #expect(policy.deployment.lockdown == (status == .malformed ? .malformed : .unavailable))
        #expect(policy.deployment.state == (status == .malformed ? .invalid : .unavailable))
        #expect(policy.deploymentMode == .airGapped && !policy.network.isValid && !policy.network.localIPC)
        #expect(!policy.scriptsEnabled && !policy.labsEnabled && policy.allowedPlugins == [])
        #expect(policy.managedKeys == Set(PolicyKey.allCases))
        for capability in PolicyCapability.allCases where capability != .audit {
            #expect(!policy.decision(for: capability).isPermitted, "\(capability)")
        }
        #expect(!policy.admission(ofPlugin: "acme", origin: .installed, capabilities: [.pluginAppearance]).isAdmitted)
        #expect(policy.admission(ofPlugin: "native.policy", origin: .system, capabilities: []).isAdmitted)
    }

    @Test func removingARestrictedProfileKeepsItRestrictedUntilTheOrganizationSaysOrdinary() {
        let store = MemoryPolicyEnrollmentStore()
        let enrolled = load(managed: internalOnly(["policy.plugins.allowed": ["acme"]]), enrollment: store)
        #expect(enrolled.deployment.state == .valid && enrolled.isRestricted)
        #expect(store.load()?.mode == .internalOnly && store.load()?.revision == enrolled.deployment.revision)

        // The profile is removed, and Native restarts with only the user's own preferences.
        let removed = load(
            user: ["policy.deployment.mode": "ordinary", "policy.plugins.allowed": ["acme"]], enrollment: store)
        #expect(removed.deployment.lockdown == .removedAfterEnrollment && removed.deployment.state == .unavailable)
        #expect(removed.deploymentMode == .internalOnly && removed.allowedPlugins == [])
        #expect(removed.decision(for: .pluginAppearance) == .disabled(.policyUnavailable))

        // A replacement profile without the mode is still not the organization's way out.
        let partial = load(managed: ["policy.plugins.allowed": ["acme"]], enrollment: store)
        #expect(partial.deployment.lockdown == .removedAfterEnrollment)

        let released = load(managed: ["policy.deployment.mode": "ordinary"], enrollment: store)
        #expect(released.deployment.lockdown == nil && !released.isRestricted)
        #expect(store.load() == nil)
        #expect(!load(enrollment: store).isRestricted)
    }

    @Test func enrollmentFileSurvivesARestartAndAnUnreadableOneStaysRestricted() throws {
        let folder = FileManager.default.temporaryDirectory.appending(
            path: "RestrictedPolicyTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Policy/enrollment.json")
        _ = load(managed: ["policy.deployment.mode": "airGapped"], enrollment: FilePolicyEnrollmentStore(url: url))
        let restarted = load(enrollment: FilePolicyEnrollmentStore(url: url))
        #expect(restarted.deploymentMode == .airGapped && restarted.deployment.lockdown == .removedAfterEnrollment)

        try Data("not json".utf8).write(to: url)
        #expect(FilePolicyEnrollmentStore(url: url).load()?.mode == .airGapped)
        _ = load(managed: ["policy.deployment.mode": "ordinary"], enrollment: FilePolicyEnrollmentStore(url: url))
        #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
    }

    @Test func restrictedModeIgnoresUserValuesAndLocksEveryKey() {
        let policy = load(
            managed: internalOnly(),
            user: [
                "policy.labs.enabled": true, "policy.plugins.allowed": ["acme"], "policy.network": ["localIPC": true],
            ])
        #expect(!policy.labsEnabled && policy.allowedPlugins == [] && !policy.network.localIPC)
        #expect(policy.keyStatus[.labsEnabled] == PolicyKeyStatus(validity: .absent, origin: .restricted))
        #expect(policy.managedKeys == Set(PolicyKey.allCases))
        // Restricting yourself isn't the organization managing anything.
        let selfRestricted = load(user: ["policy.deployment.mode": "airGapped"])
        #expect(selfRestricted.isRestricted && !selfRestricted.deployment.isManaged)
        #expect(selfRestricted.managedKeys.isEmpty)
    }

    @Test func restrictedGrantsOnlyReachConvertedCapabilities() {
        let policy = load(
            managed: internalOnly([
                "policy.scripts.enabled": true, "policy.agents.allowed": ["codex"],
                "policy.plugins.allowed": ["themes"],
                "policy.network": [
                    "services": [
                        "icons.index": ["enabled": true, "origins": ["https://art.example"]],
                        "icons.assets": ["enabled": true, "origins": ["https://art.example"]],
                    ]
                ],
            ]))
        #expect(!policy.scriptsEnabled && policy.agents.allowed == [])
        #expect(policy.keyStatus[.scriptsEnabled] == PolicyKeyStatus(validity: .valid, origin: .restricted))
        #expect(policy.allowedPlugins == ["themes"])
        #expect(policy.decision(for: .scriptRuntime) == .disabled(.notSupportedInRestrictedMode))
        #expect(policy.decision(for: .iconDownload) == .allowed)
        #expect(policy.decision(for: .celebrationDownload) == .disabled(.notSupportedInRestrictedMode))
        for capability in PolicyCapability.allCases where capability.coverage.enforcement == .unconverted {
            #expect(!policy.decision(for: capability).isPermitted || capability == .audit, "\(capability)")
        }
        #expect(policy.admission(ofPlugin: "themes", origin: .installed, capabilities: [.pluginAppearance]).isAdmitted)
        #expect(
            policy.admission(
                ofPlugin: "themes", origin: .installed, capabilities: [.pluginAppearance, .agentExecution])
                == PluginAdmission(reason: .capability(.agentExecution, .notSupportedInRestrictedMode)))
        #expect(
            policy.admission(ofPlugin: "themes", origin: .builtIn, capabilities: nil)
                == PluginAdmission(reason: .undeclared))
        #expect(
            policy.admission(ofPlugin: "sounds", origin: .builtIn, capabilities: [.sounds])
                == PluginAdmission(reason: .notAllowed))

        let withoutGrant = load(managed: internalOnly(["policy.plugins.allowed": ["themes"]]))
        #expect(withoutGrant.decision(for: .iconDownload) == .disabled(.serviceDisabled(.iconIndex)))
    }

    @Test func builtInAndInstalledPluginsGetTheSameRestrictedDecision() {
        let policies = [
            load(),
            load(managed: ["policy.plugins.allowed": ["acme"]]),
            load(managed: internalOnly(["policy.plugins.allowed": ["acme"]])),
            load(managed: ["policy.deployment.mode": "airGapped", "policy.plugins.allowed": ["other"]]),
        ]
        let declarations: [Set<PolicyCapability>?] = [nil, [], [.pluginAppearance], [.agentExecution, .iconDownload]]
        for policy in policies {
            for capabilities in declarations {
                let builtIn = policy.admission(ofPlugin: "acme", origin: .builtIn, capabilities: capabilities)
                let installed = policy.admission(ofPlugin: "acme", origin: .installed, capabilities: capabilities)
                if policy.isRestricted {
                    #expect(builtIn == installed)
                } else {
                    // Ordinary mode keeps today's rule: built-ins answer to their own keys.
                    #expect(builtIn.isAdmitted)
                }
            }
        }
        let ordinaryList = load(managed: ["policy.plugins.allowed": ["other"]])
        #expect(!ordinaryList.admission(ofPlugin: "acme", origin: .installed, capabilities: nil).isAdmitted)
        #expect(ordinaryList.admission(ofPlugin: "acme", origin: .builtIn, capabilities: nil).isAdmitted)
    }

    @Test func requiredCapabilitiesThatAreDeniedConflictAndTakeAgentsWithThem() {
        let telemetry = load(managed: [
            "policy.telemetry.native": "on",
            "policy.network": ["services": ["diagnostics.native": ["enabled": false]]],
        ])
        let native = telemetry.decision(for: .nativeDiagnostics)
        #expect(native.state == .disabled && native.conflictsWithRequirement)
        #expect(native.reason == .serviceDisabled(.nativeDiagnostics))
        #expect(
            telemetry.diagnostics.contains { $0.key == "policy.telemetry.native" && $0.problem.hasPrefix("requires") })

        let mcp = load(managed: [
            "policy.mcp.required": [["name": "audit", "command": "auditd"]],
            "policy.network": ["services": ["mcp.stdio": ["enabled": false]]],
        ])
        #expect(mcp.decision(for: .mcpExecution).conflictsWithRequirement)
        #expect(mcp.decision(for: .agentExecution) == .disabled(.requiredButDenied(.mcpExecution)))

        let satisfied = load(managed: ["policy.mcp.required": [["name": "audit", "command": "auditd"]]])
        #expect(satisfied.decision(for: .mcpExecution).state == .required)
        #expect(satisfied.decision(for: .agentExecution) == .allowed)
    }

    @Test func managedValuesBeatUserValues() {
        let policy = load(
            managed: ["policy.labs.enabled": false, "policy.plugins.allowed": ["acme"]],
            user: ["policy.labs.enabled": true, "policy.plugins.allowed": ["acme", "other"]])
        #expect(!policy.labsEnabled && policy.allowedPlugins == ["acme"])
        #expect(policy.keyStatus[.labsEnabled] == PolicyKeyStatus(validity: .valid, origin: .organization))
        #expect(policy.decision(for: .labs) == .disabled(.turnedOff(.labsEnabled)))
    }

    @Test func revisionsIdentifyTheOrganizationsInput() {
        let first = load(managed: ["policy.labs.enabled": false, "policy.agents.allowed": ["a", "b"]])
        let same = load(managed: ["policy.agents.allowed": ["a", "b"], "policy.labs.enabled": false], user: ["x": 1])
        let changed = load(managed: ["policy.labs.enabled": true, "policy.agents.allowed": ["a", "b"]])
        #expect(first.deployment.revision != nil)
        #expect(first.deployment.revision == same.deployment.revision)
        #expect(first.deployment.revision != changed.deployment.revision)
        #expect(first.deployment.revision?.value.count == 16)
        #expect(load(user: ["policy.labs.enabled": false]).deployment.revision == nil)
    }

    @Test func diagnosticsAndInspectionCarryNoSecrets() {
        let policy = load(
            managed: [
                "policy.mcp.required": [
                    [
                        "name": "docs", "url": "https://mcp.example.com/?token=SECRET-URL",
                        "headers": ["Authorization": "SECRET-H"],
                    ],
                    ["name": "bad", "url": "file:///SECRET-FILE"],
                ],
                "policy.agents.environment": ["claude-code": ["ANTHROPIC_API_KEY": "SECRET-ENV"]],
                "policy.telemetry.endpoints": [
                    ["url": "https://otel.example.com/?key=SECRET-OTEL", "headers": ["k": "SECRET-K"]]
                ],
                "policy.updates.feedURL": "https://updates.example.com/?SECRET-FEED",
                "policy.organization.name": "SECRET-ORG",
                "policy.ai.instructions": ["title": "SECRET-AI"],
                "policy.network": [
                    "services": ["icons.index": ["enabled": true, "origins": ["https://SECRET-ORIGIN.example"]]]
                ],
                "policy.network.https://SECRET-KEY.example": true,
            ])
        let text = String(describing: policy.inspection) + policy.diagnostics.map(\.description).joined()
        #expect(!text.contains("SECRET"), "\(text)")
        #expect(policy.inspection.keys.first { $0.key == .organizationName }?.value == .configured)
        #expect(policy.inspection.keys.first { $0.key == .agentsEnvironment }?.value == .count(1))
    }
}

@Suite struct PlatformPolicySourceTests {
    private func isolatedDefaults() throws -> (UserDefaults, String) {
        let suite = "RestrictedPolicyTests.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suite)), suite)
    }

    @Test func macOSForcedValuesBeatUserValuesAndLaunchArgumentsCantImpersonateThem() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "policy.labs.enabled")
        defaults.set(true, forKey: "policy.scripts.enabled")
        let forced: Set<String> = ["policy.labs.enabled", "policy.scripts.enabled"]
        func source(arguments: [String: Any]) -> UserDefaultsPolicySource {
            nonisolated(unsafe) let arguments = arguments
            return UserDefaultsPolicySource(
                defaults: defaults, simulatedManagedKeys: [], enrollment: nil, isForced: { forced.contains($0) },
                launchArguments: { arguments })
        }
        let profile = PolicyLoader.load(from: source(arguments: [:]))
        #expect(!profile.labsEnabled && profile.scriptsEnabled && profile.isManaged(.labsEnabled))
        #expect(source(arguments: [:]).userValue(forKey: "policy.labs.enabled") == nil)

        // `-policy.scripts.enabled YES` could be what `object(forKey:)` returns, so the forced key denies.
        let shadowed = PolicyLoader.load(from: source(arguments: ["policy.scripts.enabled": "YES"]))
        #expect(!shadowed.scriptsEnabled)
        #expect(shadowed.keyStatus[.scriptsEnabled] == PolicyKeyStatus(validity: .unavailable, origin: .failClosed))
        #expect(shadowed.diagnostics.map(\.problem) == ["can't be read reliably; denied"])

        // A launch argument for a key the organization doesn't manage leaves managed keys alone.
        let unmanaged = PolicyLoader.load(from: source(arguments: ["policy.companion.enabled": false]))
        #expect(unmanaged.diagnostics.isEmpty && !unmanaged.labsEnabled)
    }

    @Test func iPadConfigurationTellsAbsentFromMalformed() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = ManagedAppConfigurationPolicySource.configurationKey
        defaults.set(true, forKey: "policy.labs.enabled")
        let source = ManagedAppConfigurationPolicySource(defaults: defaults)

        #expect(source.managedStatus == .available && source.managedKeys == [])
        #expect(PolicyLoader.load(from: source).labsEnabled)

        defaults.set(["policy.labs.enabled": false, "policy.unknown": 1], forKey: key)
        let managed = PolicyLoader.load(from: source)
        #expect(!managed.labsEnabled && managed.isManaged(.labsEnabled))
        #expect(managed.diagnostics.map(\.key) == ["policy.unknown"])

        defaults.set("policy.labs.enabled=true", forKey: key)
        #expect(source.managedStatus == .malformed && source.userValue(forKey: "policy.labs.enabled") == nil)
        let malformed = PolicyLoader.load(from: source)
        #expect(malformed.deployment.lockdown == .malformed && !malformed.labsEnabled)
    }
}
