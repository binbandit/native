/// What policy says about a capability right now.
public struct CapabilityDecision: Equatable, Sendable {
    public enum State: String, Equatable, Sendable {
        /// The organization requires it; users can't turn it off.
        case required
        case allowed
        case disabled
    }

    public enum Reason: Equatable, Sendable, CustomStringConvertible {
        /// The managed configuration can't be read, or disappeared after a restricted enrollment.
        case policyUnavailable
        /// A restricted policy sets keys Native doesn't know.
        case unknownPolicyKey
        /// A managed value it depends on is malformed.
        case invalidValue(PolicyKey)
        case turnedOff(PolicyKey)
        case notConfigured(PolicyKey)
        case serviceDisabled(NativePolicy.NetworkService)
        /// Its owners don't consult this decision yet (`PolicyCapability.Enforcement.unconverted`).
        case notSupportedInRestrictedMode
        /// Something it needs is required by the organization and denied.
        case requiredButDenied(PolicyCapability)

        public var description: String {
            switch self {
            case .policyUnavailable: "policy unavailable"
            case .unknownPolicyKey: "unknown policy key"
            case .invalidValue(let key): "invalid \(key.rawValue)"
            case .turnedOff(let key): "turned off by \(key.rawValue)"
            case .notConfigured(let key): "\(key.rawValue) not configured"
            case .serviceDisabled(let service): "network service \(service.rawValue) denied"
            case .notSupportedInRestrictedMode: "not supported in restricted mode yet"
            case .requiredButDenied(let capability): "required \(capability.rawValue) is denied"
            }
        }
    }

    public var state: State
    public var reason: Reason?
    /// The organization requires it, and something else denies it.
    public var conflictsWithRequirement = false

    public var isPermitted: Bool { state != .disabled }

    static let allowed = CapabilityDecision(state: .allowed)
    static let required = CapabilityDecision(state: .required)
    static func disabled(_ reason: Reason, conflict: Bool = false) -> CapabilityDecision {
        CapabilityDecision(state: .disabled, reason: reason, conflictsWithRequirement: conflict)
    }
}

/// Whether a plugin may contribute, prepare or receive events.
public struct PluginAdmission: Equatable, Sendable {
    public enum Origin: String, Sendable {
        /// Compiled into Native and listed in Extensions.
        case builtIn
        /// A `plugin.json` the user installed.
        case installed
        /// Part of how Native runs, never listed: the organization's own policy, telemetry, task scripts.
        case system
    }

    public enum Reason: Equatable, Sendable {
        case policyUnavailable
        case unknownPolicyKey
        /// Not on `policy.plugins.allowed`.
        case notAllowed
        /// The plugin doesn't say what it does, so restricted mode can't admit it.
        case undeclared
        case capability(PolicyCapability, CapabilityDecision.Reason)
    }

    public var reason: Reason?
    public var isAdmitted: Bool { reason == nil }

    static let admitted = PluginAdmission(reason: nil)
}

extension NativePolicy {
    /// Required, allowed or disabled, and why. Restricted mode disables every capability whose
    /// owners don't consult this yet, whatever its keys say.
    public func decision(for capability: PolicyCapability) -> CapabilityDecision {
        let coverage = capability.coverage
        // Keeping a local record grants nothing, so no policy state turns it off.
        if capability == .audit { return .required }
        if let lockdown = deployment.lockdown {
            return .disabled(lockdown == .unknownKeys ? .unknownPolicyKey : .policyUnavailable)
        }
        if let key = coverage.keys.first(where: { keyStatus[$0]?.validity.isFailure == true }) {
            return .disabled(.invalidValue(key))
        }
        // In ordinary mode the user's own unusable network setting is ignored here like any other
        // user value: it never takes agents away. Native's own connections still refuse it.
        let networkFailed = isRestricted || keyStatus[.network]?.validity.isFailure == true
        if !coverage.services.isEmpty && !network.isValid && networkFailed {
            return .disabled(.invalidValue(.network))
        }
        let isRequired = requires(capability)
        if let denial = denial(of: capability) { return .disabled(denial, conflict: isRequired) }
        // An agent session can't go without the servers the organization requires.
        if capability == .agentExecution, decision(for: .mcpExecution).conflictsWithRequirement {
            return .disabled(.requiredButDenied(.mcpExecution))
        }
        return isRequired ? .required : .allowed
    }

    /// Whether a plugin may run at all. Ordinary mode keeps today's rules: `policy.plugins.allowed`
    /// covers installed plugins, and built-ins answer to their own keys (`isAllowed(by:)`).
    /// Restricted mode admits a plugin only when the organization lists it, built-in or not, and
    /// every capability it declares is permitted. `capabilities` nil means it declares none.
    public func admission(
        ofPlugin id: String, origin: PluginAdmission.Origin, capabilities: Set<PolicyCapability>?
    ) -> PluginAdmission {
        guard isRestricted else {
            return origin == .installed && !allowsPlugin(id) ? PluginAdmission(reason: .notAllowed) : .admitted
        }
        // The organization's own policy plugin needs nothing granted.
        if origin == .system, capabilities?.isEmpty == true { return .admitted }
        if let lockdown = deployment.lockdown {
            return PluginAdmission(reason: lockdown == .unknownKeys ? .unknownPolicyKey : .policyUnavailable)
        }
        if origin != .system && !allowsPlugin(id) { return PluginAdmission(reason: .notAllowed) }
        guard let capabilities else { return PluginAdmission(reason: .undeclared) }
        for capability in capabilities.sorted(by: { $0.rawValue < $1.rawValue }) {
            let decision = decision(for: capability)
            if !decision.isPermitted, let reason = decision.reason {
                return PluginAdmission(reason: .capability(capability, reason))
            }
        }
        return .admitted
    }

    private func requires(_ capability: PolicyCapability) -> Bool {
        switch capability {
        case .nativeDiagnostics: telemetry.native == .on
        case .organizationDiagnostics, .auditExport: !telemetry.endpoints.isEmpty
        case .mcpExecution: !mcp.required.isEmpty
        default: false
        }
    }

    private func denial(of capability: PolicyCapability) -> CapabilityDecision.Reason? {
        let coverage = capability.coverage
        if isRestricted && coverage.enforcement == .unconverted { return .notSupportedInRestrictedMode }
        if let key = gate(capability) { return key }
        let deniedService = coverage.services.first { service in
            let rule = network.services[service]
            return rule?.enabled == false || (isRestricted && rule?.enabled != true)
        }
        return deniedService.map(CapabilityDecision.Reason.serviceDisabled)
    }

    /// The keys that switch a capability off as a whole. Finer rules (which agents, which servers)
    /// stay with their owners.
    private func gate(_ capability: PolicyCapability) -> CapabilityDecision.Reason? {
        func off(_ isOn: Bool, _ key: PolicyKey) -> CapabilityDecision.Reason? { isOn ? nil : .turnedOff(key) }
        return switch capability {
        case .agentExecution: off(agents.allowed?.isEmpty != true, .agentsAllowed)
        case .mcpExecution: off(mcp.allowed?.isEmpty != true || !mcp.required.isEmpty, .mcpAllowed)
        case .pluginCatalog: off(catalog.isEnabled, .catalogEnabled)
        case .scriptRuntime: off(scriptsEnabled, .scriptsEnabled)
        case .userTaskScripts: off(taskScripts.userScriptsEnabled, .taskScriptsUser)
        case .repositoryTaskScripts: off(taskScripts.repositoryScriptsEnabled, .taskScriptsRepository)
        case .worktreeFetch: off(worktreeFetchEnabled, .worktreeFetch)
        case .celebrations: off(celebrationsEnabled, .celebrationsEnabled)
        case .celebrationDownload:
            off(celebrationsEnabled, .celebrationsEnabled)
                ?? off(celebrations.downloadsEnabled, .celebrationDownloadsEnabled)
        case .appUpdates, .hostUpdates: off(updates.isEnabled, .updatesEnabled)
        case .nativeDiagnostics: off(telemetry.native != .off, .telemetryNative)
        case .organizationDiagnostics, .auditExport:
            telemetry.endpoints.isEmpty ? .notConfigured(.telemetryEndpoints) : nil
        case .commandCoverage: off(unknownCommandCountsEnabled, .unknownCommandCounts)
        case .labs: off(labsEnabled, .labsEnabled)
        case .pairing: off(companionEnabled, .companionEnabled)
        case .remoteHosts: off(remoteHostsEnabled, .remoteHostsEnabled)
        default: nil
        }
    }
}

extension PolicyCapability {
    /// The key that makes it required, for reporting a conflict.
    var requiringKey: PolicyKey? {
        switch self {
        case .nativeDiagnostics: .telemetryNative
        case .organizationDiagnostics, .auditExport: .telemetryEndpoints
        case .mcpExecution: .mcpRequired
        default: nil
        }
    }
}
