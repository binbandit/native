/// Every managed setting Native reads, by the preference key an organization's configuration profile
/// sets. See `docs/enterprise.md` and the package-only catalog inputs in `docs/catalog-policy.md`.
public enum PolicyKey: String, CaseIterable, Hashable, Sendable {
    case agentsAllowed = "policy.agents.allowed"
    case agentsEnvironment = "policy.agents.environment"
    case mcpAllowed = "policy.mcp.allowed"
    case mcpBlocked = "policy.mcp.blocked"
    case mcpRequired = "policy.mcp.required"
    case pluginsAllowed = "policy.plugins.allowed"
    case catalogEnabled = "policy.catalog.enabled"
    case catalogIndexURL = "policy.catalog.indexURL"
    case skillsBlocked = "policy.skills.blocked"
    case forbiddenPermissionModes = "policy.permissions.forbiddenModes"
    case scriptsEnabled = "policy.scripts.enabled"
    case taskScriptsUser = "policy.taskScripts.userScripts"
    case taskScriptsRepository = "policy.taskScripts.repositoryScripts"
    case labsEnabled = "policy.labs.enabled"
    case companionEnabled = "policy.companion.enabled"
    case remoteHostsEnabled = "policy.remoteHosts.enabled"
    case updatesFeedURL = "policy.updates.feedURL"
    case updatesEnabled = "policy.updates.enabled"
    case updatesChannels = "policy.updates.channels"
    case searchRetentionDays = "policy.search.retentionDays"
    case shortcutBindings = "policy.shortcuts.bindings"
    case aiInstructions = "policy.ai.instructions"
    case telemetryNative = "policy.telemetry.native"
    case telemetryEndpoints = "policy.telemetry.endpoints"

    /// The prefix every policy key shares; managed keys under it that Native doesn't know are reported.
    public static let prefix = "policy."
}
