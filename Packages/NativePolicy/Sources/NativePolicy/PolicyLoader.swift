import ApprovalAnalysis
import CodeThemeCatalog
import Foundation

/// Reads and validates every policy key from a source.
public enum PolicyLoader {
    public static func load(from source: any PolicySource) -> NativePolicy {
        let deployment = DeploymentResolution(source: source)
        var resolver = PolicyResolver(
            source: source, isRestricted: deployment.mode != .ordinary, isTrusted: deployment.isTrusted)
        var policy = NativePolicy()
        policy.foldersAllowedRoots = resolver.resolve(
            .foldersAllowedRoots, expecting: "an array of absolute local folder paths", ordinary: nil, restricted: [],
            invalid: [], PolicyParse.folderRoots)
        policy.organizationContact = resolver.resolve(
            .organizationContact, expecting: "a non-empty string", ordinary: nil, restricted: nil, PolicyParse.text)
        // An unusable theme leaves the user's own, as the theme isn't a security setting.
        policy.appearanceCodeTheme = resolver.resolve(
            .appearanceCodeTheme, expecting: "a built-in code theme id", ordinary: nil, restricted: nil,
            PolicyParse.codeTheme)
        policy.appearanceCodeThemeReason = resolver.resolve(
            .appearanceCodeThemeReason, expecting: "a non-empty string", ordinary: nil, restricted: nil,
            PolicyParse.text)
        policy.commandKnowledge = resolver.resolve(
            .commandKnowledge, expecting: "a command knowledge JSON document", ordinary: .init(), restricted: .init(),
            PolicyParse.commandKnowledge)
        policy.unknownCommandCountsEnabled = resolver.resolve(
            .unknownCommandCounts, expecting: "a Boolean", ordinary: true, restricted: false, PolicyParse.bool)
        policy.agents.allowed = resolver.resolve(
            .agentsAllowed, expecting: "an array of agent ids", ordinary: nil, restricted: [], PolicyParse.stringSet)
        policy.agents.environment = resolver.resolve(
            .agentsEnvironment, expecting: "a dictionary of agent ids to environment dictionaries", ordinary: [:],
            restricted: [:], PolicyParse.environment)
        policy.mcp.allowed = resolver.resolve(
            .mcpAllowed, expecting: "an array of server names or command: patterns", ordinary: nil, restricted: [],
            PolicyParse.patterns)
        policy.mcp.blocked = resolver.resolve(
            .mcpBlocked, expecting: "an array of server names or command: patterns", ordinary: [], restricted: [],
            PolicyParse.patterns)
        policy.mcp.required = resolver.resolve(
            .mcpRequired, expecting: "an array of servers, each with a name and exactly one of command or url",
            ordinary: [], restricted: [], PolicyParse.requiredServers)
        policy.allowedPlugins = resolver.resolve(
            .pluginsAllowed, expecting: "an array of plugin ids", ordinary: nil, restricted: [], PolicyParse.stringSet)
        policy.celebrations.downloadsEnabled = resolver.resolve(
            .celebrationDownloadsEnabled, expecting: "a Boolean", ordinary: true, restricted: false, PolicyParse.bool)
        policy.celebrations.baseURL = resolver.resolve(
            .celebrationAssetsBaseURL, expecting: "an http or https URL", ordinary: nil, restricted: nil,
            PolicyParse.webURL)
        policy.catalog.isEnabled = resolver.resolve(
            .catalogEnabled, expecting: "a Boolean", ordinary: true, restricted: false, PolicyParse.bool)
        policy.catalog.indexURL = resolver.resolve(
            .catalogIndexURL, expecting: "an http or https URL", ordinary: nil, restricted: nil, PolicyParse.webURL)
        policy.blockedSkills = resolver.resolve(
            .skillsBlocked, expecting: "an array of skill names", ordinary: [], restricted: [], PolicyParse.strings)
        policy.forbiddenPermissionModes = resolver.resolve(
            .forbiddenPermissionModes, expecting: "an array of permission mode ids", ordinary: [], restricted: [],
            PolicyParse.stringSet)
        policy.scriptsEnabled = resolver.resolve(
            .scriptsEnabled, expecting: "a Boolean", ordinary: true, restricted: false, PolicyParse.bool)
        policy.sourceExcerptsSendingEnabled = resolver.resolve(
            .sourceExcerptsSending, expecting: "a Boolean", ordinary: true, restricted: false, PolicyParse.bool)
        policy.sourceExcerptsRetentionEnabled = resolver.resolve(
            .sourceExcerptsRetention, expecting: "a Boolean", ordinary: true, restricted: false, PolicyParse.bool)
        policy.worktreeFetchEnabled = resolver.resolve(
            .worktreeFetch, expecting: "a Boolean", ordinary: true, restricted: false, PolicyParse.bool)
        policy.taskScripts.userScriptsEnabled = resolver.resolve(
            .taskScriptsUser, expecting: "a Boolean", ordinary: true, restricted: false, PolicyParse.bool)
        policy.taskScripts.repositoryScriptsEnabled = resolver.resolve(
            .taskScriptsRepository, expecting: "a Boolean", ordinary: true, restricted: false, PolicyParse.bool)
        policy.celebrationsEnabled = resolver.resolve(
            .celebrationsEnabled, expecting: "a Boolean", ordinary: true, restricted: false, PolicyParse.bool)
        policy.organizationName = resolver.resolve(
            .organizationName, expecting: "a nonempty organization name", ordinary: nil, restricted: nil,
            PolicyParse.organizationName)
        policy.labsEnabled = resolver.resolve(
            .labsEnabled, expecting: "a Boolean", ordinary: true, restricted: false, PolicyParse.bool)
        policy.companionEnabled = resolver.resolve(
            .companionEnabled, expecting: "a Boolean", ordinary: true, restricted: false, PolicyParse.bool)
        policy.remoteHostsEnabled = resolver.resolve(
            .remoteHostsEnabled, expecting: "a Boolean", ordinary: true, restricted: false, PolicyParse.bool)
        policy.updates.isEnabled = resolver.resolve(
            .updatesEnabled, expecting: "a Boolean", ordinary: true, restricted: false, PolicyParse.bool)
        policy.updates.feedURL = resolver.resolve(
            .updatesFeedURL, expecting: "an http or https URL", ordinary: nil, restricted: nil, PolicyParse.webURL)
        policy.updates.allowedChannels = resolver.resolve(
            .updatesChannels, expecting: "an array of stable, beta or nightly", ordinary: nil, restricted: [],
            PolicyParse.channels)
        // Unusable retention keeps everything: any period Native picked could delete what the
        // organization meant to keep, and the key is still reported and counted as failed.
        policy.searchRetentionDays = resolver.resolve(
            .searchRetentionDays, expecting: "a whole number of days, 1 or more", ordinary: nil, restricted: nil,
            PolicyParse.positiveInt)
        // Unusable shortcuts or instructions lock Native's own, rather than leaving the user's.
        policy.shortcutBindings = resolver.resolve(
            .shortcutBindings, expecting: "a dictionary of command ids to shortcuts", ordinary: nil, restricted: nil,
            invalid: [:], PolicyParse.stringDictionary)
        policy.aiInstructions = resolver.resolve(
            .aiInstructions, expecting: "a dictionary of purpose ids to instructions", ordinary: nil,
            restricted: nil, invalid: [:], PolicyParse.stringDictionary)
        policy.telemetry.native = resolver.resolve(
            .telemetryNative, expecting: "on, off or user", ordinary: .user, restricted: .off,
            PolicyParse.telemetryMode)
        policy.telemetry.endpoints = resolver.resolve(
            .telemetryEndpoints, expecting: "an array of collectors, each with an http or https url", ordinary: [],
            restricted: [], PolicyParse.endpoints)
        policy.keyStatus = resolver.statuses
        policy.deployment = deployment.deployment
        policy.diagnostics = deployment.diagnostics + resolver.diagnostics + unknownKeys(in: source)
        loadNetwork(from: source, deployment: deployment, into: &policy)
        policy.failClosed()
        policy.settle()
        return policy
    }

    /// Managed keys under `policy.` that Native doesn't know, which are usually typos.
    private static func unknownKeys(in source: any PolicySource) -> [PolicyDiagnostic] {
        DeploymentResolution.unknownKeys(in: source)
            // Network parsing reports these without echoing untrusted configuration keys.
            .filter { !$0.hasPrefix("policy.network.") && !$0.hasPrefix("policy.deployment.") }
            .map { PolicyDiagnostic(key: $0, origin: .organization, problem: "isn't a Native policy key") }
    }
}

extension NativePolicy {
    /// What an unusable security value takes with it, beyond its own key: an agent session the
    /// organization meant to shape some way it can't, a download whose destination it can't read.
    fileprivate mutating func failClosed() {
        func failed(_ key: PolicyKey) -> Bool { keyStatus[key]?.validity.isFailure == true }
        let agentKeys: [PolicyKey] = [.agentsEnvironment, .forbiddenPermissionModes, .skillsBlocked, .mcpRequired]
        if let key = agentKeys.first(where: failed), agents.allowed != [] {
            agents.allowed = []
            diagnostics.append(
                PolicyDiagnostic(
                    key: key.rawValue, origin: .organization, problem: "agents are denied until it's fixed"))
        }
        if failed(.mcpBlocked) { mcp.allowed = [] }
        if failed(.updatesFeedURL) || failed(.updatesChannels) { updates.isEnabled = false }
        if failed(.celebrationAssetsBaseURL) { celebrations.downloadsEnabled = false }
        if failed(.catalogIndexURL) { catalog.isEnabled = false }
    }

    /// Settles which keys the organization controls and how its configuration read, once every key is in.
    fileprivate mutating func settle() {
        let managed = keyStatus.filter { $0.value.validity != .absent }.map(\.key)
        managedKeys.formUnion(managed)
        // Under an organization's restricted mode every key is its call, set or not.
        if isRestricted && deployment.isManaged { managedKeys = Set(PolicyKey.allCases) }
        guard deployment.lockdown == nil else { return }
        let failed = keyStatus.values.contains { $0.validity.isFailure } || (!network.isValid && deployment.isManaged)
        deployment.state = failed ? .invalid : deployment.revision == nil ? .absent : .valid
        for capability in PolicyCapability.allCases {
            let decision = decision(for: capability)
            guard decision.conflictsWithRequirement, let key = capability.requiringKey else { continue }
            diagnostics.append(
                PolicyDiagnostic(
                    key: key.rawValue, origin: .organization,
                    problem: "requires \(capability.rawValue), which is denied (\(decision.reason?.description ?? ""))")
            )
        }
    }
}

/// Parsers for property-list values. Each returns nil when the value as a whole is unusable, and
/// reports entries it skipped in `problems`.
enum PolicyParse {
    static func folderRoots(_ raw: Any, _ problems: inout [String]) -> [String]? {
        guard let roots = raw as? [String],
            roots.allSatisfy({
                $0.hasPrefix("/") && !$0.contains("\0") && !$0.hasPrefix("//")
            })
        else { return nil }
        return roots.map { URL(filePath: $0).standardizedFileURL.path }
    }

    static func text(_ raw: Any, _ problems: inout [String]) -> String? {
        guard let text = raw as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return text
    }

    static func codeTheme(_ raw: Any, _ problems: inout [String]) -> String? {
        guard let id = raw as? String, CodeTheme.theme(id: .init(rawValue: id)) != nil else { return nil }
        return id
    }

    static func commandKnowledge(_ raw: Any, _ problems: inout [String]) -> CommandKnowledge? {
        guard let json = raw as? String else { return nil }
        let knowledge = CommandKnowledge.load(Data(json.utf8))
        problems += knowledge.problems
        return knowledge
    }

    /// Property-list Booleans only: 1, "true" and "YES" aren't.
    static func bool(_ raw: Any, _ problems: inout [String]) -> Bool? {
        guard let number = raw as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    static func organizationName(_ raw: Any, _ problems: inout [String]) -> String? {
        guard let text = raw as? String else { return nil }
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    static func strings(_ raw: Any, _ problems: inout [String]) -> [String]? {
        guard let array = raw as? [Any] else { return nil }
        var strings: [String] = []
        for (index, element) in array.enumerated() {
            guard let string = element as? String, !string.trimmingCharacters(in: .whitespaces).isEmpty else {
                problems.append("item \(index + 1) isn't a non-empty string; skipped")
                continue
            }
            strings.append(string.trimmingCharacters(in: .whitespaces))
        }
        return strings
    }

    static func stringSet(_ raw: Any, _ problems: inout [String]) -> Set<String>? {
        strings(raw, &problems).map(Set.init)
    }

    static func patterns(_ raw: Any, _ problems: inout [String]) -> [MCPServerPattern]? {
        strings(raw, &problems)?.compactMap { string in
            let pattern = MCPServerPattern(string)
            if pattern == nil { problems.append("an empty command: pattern; skipped") }
            return pattern
        }
    }

    static func environment(_ raw: Any, _ problems: inout [String]) -> [String: [String: String]]? {
        guard let dictionary = raw as? [String: Any] else { return nil }
        var environment: [String: [String: String]] = [:]
        for (agent, value) in dictionary {
            guard let variables = value as? [String: String] else {
                problems.append("\(agent) should be a dictionary of strings; skipped")
                continue
            }
            environment[agent] = variables
        }
        return environment
    }

    static func stringDictionary(_ raw: Any, _ problems: inout [String]) -> [String: String]? {
        guard let dictionary = raw as? [String: Any] else { return nil }
        var strings: [String: String] = [:]
        for (key, value) in dictionary {
            guard let string = value as? String else {
                problems.append("\(key) should be a string; skipped")
                continue
            }
            strings[key] = string
        }
        return strings
    }

    static func webURL(_ raw: Any, _ problems: inout [String]) -> URL? {
        guard let string = raw as? String, let url = URL(string: string),
            let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http", url.host() != nil
        else { return nil }
        return url
    }

    static let knownChannels: Set<String> = ["stable", "beta", "nightly"]

    static func channels(_ raw: Any, _ problems: inout [String]) -> Set<String>? {
        guard let names = strings(raw, &problems) else { return nil }
        var channels = Set<String>()
        for name in names {
            if knownChannels.contains(name.lowercased()) {
                channels.insert(name.lowercased())
            } else {
                problems.append("\(name) isn't a channel; skipped")
            }
        }
        return channels
    }

    static func positiveInt(_ raw: Any, _ problems: inout [String]) -> Int? {
        guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
            number.doubleValue == number.doubleValue.rounded(), number.intValue >= 1
        else { return nil }
        return number.intValue
    }

    static func telemetryMode(_ raw: Any, _ problems: inout [String]) -> NativePolicy.Telemetry.NativeMode? {
        (raw as? String).flatMap { NativePolicy.Telemetry.NativeMode(rawValue: $0.lowercased()) }
    }

    static func requiredServers(_ raw: Any, _ problems: inout [String]) -> [RequiredMCPServer]? {
        guard let array = raw as? [Any] else { return nil }
        var servers: [RequiredMCPServer] = []
        for (index, element) in array.enumerated() {
            guard let entry = element as? [String: Any], let name = entry["name"] as? String, !name.isEmpty else {
                problems.append("server \(index + 1) has no name; skipped")
                continue
            }
            // Present but mistyped is a problem, never silently empty: a header may carry the server's auth.
            guard let arguments = optional(entry["args"], as: [String].self, default: []),
                let environment = optional(entry["env"], as: [String: String].self, default: [:]),
                let headers = optional(entry["headers"], as: [String: String].self, default: [:])
            else {
                problems.append("\(name)'s args, env or headers have the wrong type; skipped")
                continue
            }
            switch (entry["command"], entry["url"]) {
            case (let command as String, nil) where !command.isEmpty:
                servers.append(
                    RequiredMCPServer(
                        name: name,
                        transport: .stdio(command: command, arguments: arguments, environment: environment)))
            case (nil, let url?):
                var ignored: [String] = []
                guard let url = webURL(url, &ignored) else {
                    problems.append("\(name)'s url isn't an http or https URL; skipped")
                    continue
                }
                servers.append(RequiredMCPServer(name: name, transport: .http(url: url, headers: headers)))
            default:
                problems.append("\(name) needs exactly one of command or url; skipped")
            }
        }
        return servers
    }

    static func endpoints(_ raw: Any, _ problems: inout [String]) -> [TelemetryEndpoint]? {
        guard let array = raw as? [Any] else { return nil }
        var endpoints: [TelemetryEndpoint] = []
        for (index, element) in array.enumerated() {
            var ignored: [String] = []
            guard let entry = element as? [String: Any], let rawURL = entry["url"], let url = webURL(rawURL, &ignored)
            else {
                problems.append("collector \(index + 1) has no http or https url; skipped")
                continue
            }
            guard let headers = optional(entry["headers"], as: [String: String].self, default: [:]),
                let attributes = optional(entry["attributes"], as: [String: String].self, default: [:])
            else {
                problems.append("collector \(index + 1)'s headers or attributes have the wrong type; skipped")
                continue
            }
            endpoints.append(TelemetryEndpoint(url: url, headers: headers, attributes: attributes))
        }
        return endpoints
    }

    /// An optional field: its default when missing, nil when present with the wrong type.
    private static func optional<Value>(_ raw: Any?, as type: Value.Type, default value: Value) -> Value? {
        guard let raw else { return value }
        return raw as? Value
    }
}
