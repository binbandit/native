/// Every family of data Native keeps, or knows other owners keep, about the user's work. The raw
/// values are stable: plans, tombstones and audit records name stores by them, so a store is never
/// renamed, only added. `DataStoreInventory.native` describes each one.
public enum DataStoreID: String, CaseIterable, Codable, Comparable, Sendable {
    // The background host.
    case hostDatabase = "host.database"
    case hostRuntime = "host.runtime"
    case hostCredentials = "host.credentials"
    case hostPairingIdentity = "host.pairingIdentity"
    case orchestrationTokenSecret = "orchestration.tokenSecret"
    case hostUpdates = "host.updates"

    // The app's own records.
    case sessionCatalog = "app.sessionCatalog"
    case drafts = "app.drafts"
    case sessionState = "app.sessionState"
    case projects = "app.projects"
    case repositoryTrust = "app.repositoryTrust"
    case settings = "app.settings"
    case usage = "app.usage"
    case policyEnrollment = "app.policyEnrollment"
    case mcpServers = "mcp.servers"
    case mcpSecrets = "mcp.secrets"
    case hostPairings = "pairing.hosts"
    case companionPairings = "pairing.companion"

    case searchIndex = "search.index"

    case automation = "automation.store"
    case expeditions = "expeditions.store"
    case expeditionDocuments = "expeditions.documents"

    // Attachments and task or pull request artifacts.
    case attachments = "temp.attachments"
    case workingFiles = "temp.workingFiles"
    case pullRequestQuestions = "github.pullRequestQuestions"
    case pullRequestClones = "github.pullRequestClones"

    case taskWorktrees = "git.taskWorktrees"
    case nativeRefs = "git.nativeRefs"
    case repositoryHistory = "git.repositoryHistory"

    // Plugins, skills, components and downloaded resources.
    case plugins = "plugins.installed"
    case componentCaches = "components.caches"
    case skillsLibrary = "skills.library"
    case skillsInstalled = "skills.installed"
    case skillsTrash = "skills.trash"
    case agentIcons = "icons.agents"
    case projectIcons = "icons.projects"
    case celebrationAssets = "celebrations.assets"
    case appUpdates = "updates.app"

    case telemetrySentLog = "diagnostics.sentLog"
    case crashReportCache = "diagnostics.crashReportCache"
    case commandCoverage = "diagnostics.commandCoverage"
    case systemRecords = "diagnostics.system"

    case approvalAudit = "audit.approvals"

    // Owned by someone other than Native.
    case agentHistories = "agents.histories"
    case agentConfiguration = "agents.configuration"
    case agentCredentials = "agents.credentials"
    case toolCredentials = "tools.credentials"
    case packageCaches = "tools.packageCaches"
    case customerBackups = "customer.backups"
    case customerExports = "customer.exports"
    case remoteHostCopies = "remote.hostCopies"

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// One physical form a store's record takes. A SQLite row can outlive its delete in the write-ahead
/// log, a removed folder can sit in a trash, a git snapshot in loose objects: each is its own copy,
/// with its own result in a plan.
public enum DataCopyKind: String, CaseIterable, Codable, Comparable, Sendable {
    case primary
    /// A SQLite `-wal` file, which holds recent pages, deleted rows included, until a checkpoint.
    case writeAheadLog
    /// A SQLite `-shm` index of the write-ahead log.
    case sharedMemory
    /// A file made for one use (a pasted image, a generated configuration).
    case temporary
    /// A copy kept so a removal can be undone.
    case trash
    /// Git objects (loose or packed) that refs no longer reach, until `git gc` prunes them.
    case gitObjects
    case reflog

    public static func < (lhs: Self, rhs: Self) -> Bool {
        allCases.firstIndex(of: lhs) ?? 0 < allCases.firstIndex(of: rhs) ?? 0
    }
}
