import ApprovalAnalysis

/// The effective policy as an administrator or support would read it: every key and capability
/// with its value, where it came from, whether the organization's input was valid, and the code
/// that has to honor it. Content-free by construction: values are summarized as switches, counts,
/// closed options or "configured", never the strings, URLs, headers or environment behind them.
public struct PolicyInspection: Equatable, Sendable, CustomStringConvertible {
    public struct Key: Equatable, Sendable {
        public let key: PolicyKey
        public let role: PolicyKey.Role
        public let validity: PolicyKeyStatus.Validity
        public let origin: PolicyKeyStatus.Origin
        public let value: PolicyValueSummary
        public let capabilities: [PolicyCapability]
        public let owners: [String]
    }

    public struct Capability: Equatable, Sendable {
        public let capability: PolicyCapability
        public let decision: CapabilityDecision
        public let kind: PolicyCapability.Kind
        public let enforcement: PolicyCapability.Enforcement
        public let keys: [PolicyKey]
        public let services: [NativePolicy.NetworkService]
        public let owners: [String]
    }

    public let mode: NativePolicy.DeploymentMode
    public let state: NativePolicy.Deployment.State
    public let lockdown: NativePolicy.Deployment.Lockdown?
    public let revision: PolicyRevision?
    public let enrollment: PolicyEnrollment?
    public let keys: [Key]
    public let capabilities: [Capability]
    public let diagnostics: [PolicyDiagnostic]

    public var description: String {
        var lines = [
            "mode \(mode.rawValue), \(state.rawValue)" + (lockdown.map { ", lockdown \($0.rawValue)" } ?? "")
                + (revision.map { ", revision \($0)" } ?? "")
        ]
        lines += keys.map { "\($0.key.rawValue): \($0.value) (\($0.origin.rawValue), \($0.validity.rawValue))" }
        lines += capabilities.map { entry in
            let reason = entry.decision.reason.map { " - \($0)" } ?? ""
            return
                "\(entry.capability.rawValue): \(entry.decision.state.rawValue)\(reason) [\(entry.enforcement.rawValue)]"
        }
        return lines.joined(separator: "\n")
    }
}

/// A key's effective value without its content.
public enum PolicyValueSummary: Equatable, Sendable, CustomStringConvertible {
    case unset
    case on
    case off
    case count(Int)
    case days(Int)
    /// One of a closed set of values Native defines (a mode or channel name), never free text.
    case option(String)
    /// Set to text or a URL, which inspection doesn't repeat.
    case configured

    public var description: String {
        switch self {
        case .unset: "unset"
        case .on: "on"
        case .off: "off"
        case .count(let count): "\(count) entries"
        case .days(let days): "\(days) days"
        case .option(let option): option
        case .configured: "configured"
        }
    }
}

extension NativePolicy {
    public var inspection: PolicyInspection {
        PolicyInspection(
            mode: deploymentMode, state: deployment.state, lockdown: deployment.lockdown,
            revision: deployment.revision, enrollment: deployment.enrollment,
            keys: PolicyKey.allCases.map { key in
                let status = keyStatus[key] ?? .ordinaryDefault
                return PolicyInspection.Key(
                    key: key, role: key.role, validity: status.validity, origin: status.origin, value: summary(of: key),
                    capabilities: key.capabilities, owners: key.owners)
            },
            capabilities: PolicyCapability.allCases.map { capability in
                let coverage = capability.coverage
                return PolicyInspection.Capability(
                    capability: capability, decision: decision(for: capability), kind: coverage.kind,
                    enforcement: coverage.enforcement, keys: coverage.keys, services: coverage.services,
                    owners: coverage.owners)
            },
            diagnostics: diagnostics)
    }

    func summary(of key: PolicyKey) -> PolicyValueSummary {
        func flag(_ value: Bool) -> PolicyValueSummary { value ? .on : .off }
        func count(_ value: (some Collection)?) -> PolicyValueSummary { value.map { .count($0.count) } ?? .unset }
        func text(_ value: Any?) -> PolicyValueSummary { value == nil ? .unset : .configured }
        return switch key {
        case .foldersAllowedRoots: count(foldersAllowedRoots)
        case .deploymentMode: .option(deploymentMode.rawValue)
        case .network: network.services.isEmpty ? .unset : .count(network.services.count)
        case .commandKnowledge: commandKnowledge == CommandKnowledge() ? .unset : .configured
        case .unknownCommandCounts: flag(unknownCommandCountsEnabled)
        case .agentsAllowed: count(agents.allowed)
        case .agentsEnvironment: agents.environment.isEmpty ? .unset : .count(agents.environment.count)
        case .mcpAllowed: count(mcp.allowed)
        case .mcpBlocked: count(mcp.blocked)
        case .mcpRequired: count(mcp.required)
        case .pluginsAllowed: count(allowedPlugins)
        case .celebrationDownloadsEnabled: flag(celebrations.downloadsEnabled)
        case .celebrationAssetsBaseURL: text(celebrations.baseURL)
        case .catalogEnabled: flag(catalog.isEnabled)
        case .catalogIndexURL: text(catalog.indexURL)
        case .skillsBlocked: count(blockedSkills)
        case .forbiddenPermissionModes: count(forbiddenPermissionModes)
        case .scriptsEnabled: flag(scriptsEnabled)
        case .worktreeFetch: flag(worktreeFetchEnabled)
        case .taskScriptsUser: flag(taskScripts.userScriptsEnabled)
        case .taskScriptsRepository: flag(taskScripts.repositoryScriptsEnabled)
        case .celebrationsEnabled: flag(celebrationsEnabled)
        case .organizationName: text(organizationName)
        case .organizationContact: text(organizationContact)
        // Theme ids are Native's own built-in set (`PolicyParse.codeTheme`).
        case .appearanceCodeTheme: appearanceCodeTheme.map(PolicyValueSummary.option) ?? .unset
        case .appearanceCodeThemeReason: text(appearanceCodeThemeReason)
        case .labsEnabled: flag(labsEnabled)
        case .companionEnabled: flag(companionEnabled)
        case .remoteHostsEnabled: flag(remoteHostsEnabled)
        case .updatesFeedURL: text(updates.feedURL)
        case .updatesEnabled: flag(updates.isEnabled)
        case .updatesChannels:
            // Channel names are Native's own closed set (`PolicyParse.knownChannels`).
            updates.allowedChannels.map { $0.isEmpty ? .count(0) : .option($0.sorted().joined(separator: ",")) }
                ?? .unset
        case .searchRetentionDays: searchRetentionDays.map(PolicyValueSummary.days) ?? .unset
        case .shortcutBindings: count(shortcutBindings)
        case .aiInstructions: count(aiInstructions)
        case .telemetryNative: .option(telemetry.native.rawValue)
        case .telemetryEndpoints: count(telemetry.endpoints)
        }
    }
}
