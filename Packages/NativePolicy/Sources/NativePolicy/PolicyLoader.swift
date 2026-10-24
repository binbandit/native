import CodeThemes
import Foundation

/// Reads and validates every policy key from a source.
public enum PolicyLoader {
    public static func load(from source: any PolicySource) -> NativePolicy {
        var resolver = PolicyResolver(source: source)
        var policy = NativePolicy()
        policy.organizationName = resolver.resolve(.organizationName, expecting: "a non-empty string", PolicyParse.text)
        policy.organizationContact = resolver.resolve(
            .organizationContact, expecting: "a non-empty string", PolicyParse.text)
        policy.appearanceCodeTheme = resolver.resolve(
            .appearanceCodeTheme, expecting: "a built-in code theme id", PolicyParse.codeTheme)
        policy.appearanceCodeThemeReason = resolver.resolve(
            .appearanceCodeThemeReason, expecting: "a non-empty string", PolicyParse.text)
        policy.agents.allowed = resolver.resolve(
            .agentsAllowed, expecting: "an array of agent ids", PolicyParse.stringSet)
        policy.agents.environment =
            resolver.resolve(
                .agentsEnvironment, expecting: "a dictionary of agent ids to environment dictionaries",
                PolicyParse.environment) ?? [:]
        policy.mcp.allowed = resolver.resolve(
            .mcpAllowed, expecting: "an array of server names or command: patterns", PolicyParse.patterns)
        policy.mcp.blocked =
            resolver.resolve(
                .mcpBlocked, expecting: "an array of server names or command: patterns", PolicyParse.patterns) ?? []
        policy.mcp.required =
            resolver.resolve(
                .mcpRequired, expecting: "an array of servers, each with a name and exactly one of command or url",
                PolicyParse.requiredServers) ?? []
        policy.allowedPlugins = resolver.resolve(
            .pluginsAllowed, expecting: "an array of plugin ids", PolicyParse.stringSet)
        policy.celebrations.downloadsEnabled =
            resolver.resolve(.celebrationDownloadsEnabled, expecting: "a Boolean", PolicyParse.bool) ?? true
        policy.celebrations.baseURL = resolver.resolve(
            .celebrationAssetsBaseURL, expecting: "an http or https URL", PolicyParse.webURL)
        policy.catalog.isEnabled = resolver.resolve(.catalogEnabled, expecting: "a Boolean", PolicyParse.bool) ?? true
        policy.catalog.indexURL = resolver.resolve(
            .catalogIndexURL, expecting: "an http or https URL", PolicyParse.webURL)
        policy.blockedSkills =
            resolver.resolve(.skillsBlocked, expecting: "an array of skill names", PolicyParse.strings) ?? []
        policy.forbiddenPermissionModes =
            resolver.resolve(
                .forbiddenPermissionModes, expecting: "an array of permission mode ids", PolicyParse.stringSet) ?? []
        policy.scriptsEnabled = resolver.resolve(.scriptsEnabled, expecting: "a Boolean", PolicyParse.bool) ?? true
        policy.worktreeFetchEnabled = resolver.resolve(.worktreeFetch, expecting: "a Boolean", PolicyParse.bool) ?? true
        policy.taskScripts.userScriptsEnabled =
            resolver.resolve(.taskScriptsUser, expecting: "a Boolean", PolicyParse.bool) ?? true
        policy.taskScripts.repositoryScriptsEnabled =
            resolver.resolve(.taskScriptsRepository, expecting: "a Boolean", PolicyParse.bool) ?? true
        policy.labsEnabled = resolver.resolve(.labsEnabled, expecting: "a Boolean", PolicyParse.bool) ?? true
        policy.companionEnabled = resolver.resolve(.companionEnabled, expecting: "a Boolean", PolicyParse.bool) ?? true
        policy.remoteHostsEnabled =
            resolver.resolve(.remoteHostsEnabled, expecting: "a Boolean", PolicyParse.bool) ?? true
        policy.updates.isEnabled = resolver.resolve(.updatesEnabled, expecting: "a Boolean", PolicyParse.bool) ?? true
        policy.updates.feedURL = resolver.resolve(
            .updatesFeedURL, expecting: "an http or https URL", PolicyParse.webURL)
        policy.updates.allowedChannels =
            resolver.resolve(.updatesChannels, expecting: "an array of stable, beta or nightly", PolicyParse.channels)
        policy.searchRetentionDays =
            resolver.resolve(
                .searchRetentionDays, expecting: "a whole number of days, 1 or more", PolicyParse.positiveInt)
        policy.shortcutBindings = resolver.resolve(
            .shortcutBindings, expecting: "a dictionary of command ids to shortcuts", PolicyParse.stringDictionary)
        policy.aiInstructions = resolver.resolve(
            .aiInstructions, expecting: "a dictionary of purpose ids to instructions", PolicyParse.stringDictionary)
        policy.telemetry.native =
            resolver.resolve(.telemetryNative, expecting: "on, off or user", PolicyParse.telemetryMode) ?? .user
        policy.telemetry.endpoints =
            resolver.resolve(
                .telemetryEndpoints, expecting: "an array of collectors, each with an http or https url",
                PolicyParse.endpoints) ?? []
        policy.managedKeys = resolver.managedKeys
        policy.diagnostics = resolver.diagnostics + unknownKeys(in: source)
        return policy
    }

    /// Managed keys under `policy.` that Native doesn't know, which are usually typos.
    private static func unknownKeys(in source: any PolicySource) -> [PolicyDiagnostic] {
        let known = Set(PolicyKey.allCases.map(\.rawValue))
        return (source.managedKeys ?? [])
            .filter { $0.hasPrefix(PolicyKey.prefix) && !known.contains($0) }
            .sorted()
            .map { PolicyDiagnostic(key: $0, origin: .organization, problem: "isn't a Native policy key") }
    }
}

/// Applies the precedence: the organization's value, then the user's, then nil for the default. A
/// value that doesn't parse is reported and the next one is tried.
struct PolicyResolver {
    let source: any PolicySource
    private(set) var managedKeys: Set<PolicyKey> = []
    private(set) var diagnostics: [PolicyDiagnostic] = []

    init(source: any PolicySource) {
        self.source = source
    }

    mutating func resolve<Value>(
        _ key: PolicyKey, expecting expected: String, _ parse: (Any, inout [String]) -> Value?
    ) -> Value? {
        if let raw = source.managedValue(forKey: key.rawValue) {
            if let value = parsed(raw, key: key, origin: .organization, expected: expected, parse) {
                managedKeys.insert(key)
                return value
            }
        }
        if let raw = source.userValue(forKey: key.rawValue) {
            return parsed(raw, key: key, origin: .user, expected: expected, parse)
        }
        return nil
    }

    private mutating func parsed<Value>(
        _ raw: Any, key: PolicyKey, origin: PolicyDiagnostic.Origin, expected: String,
        _ parse: (Any, inout [String]) -> Value?
    ) -> Value? {
        var problems: [String] = []
        let value = parse(raw, &problems)
        if value == nil {
            diagnostics.append(
                PolicyDiagnostic(key: key.rawValue, origin: origin, problem: "should be \(expected); ignored"))
        }
        diagnostics += problems.map { PolicyDiagnostic(key: key.rawValue, origin: origin, problem: $0) }
        return value
    }
}

/// Parsers for property-list values. Each returns nil when the value as a whole is unusable, and
/// reports entries it skipped in `problems`.
enum PolicyParse {
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

    static func bool(_ raw: Any, _ problems: inout [String]) -> Bool? {
        guard let number = raw as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return raw as? Bool }
        return number.boolValue
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
        strings(raw, &problems)?.compactMap { MCPServerPattern($0) }
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
            switch (entry["command"] as? String, entry["url"]) {
            case (let command?, nil) where !command.isEmpty:
                servers.append(
                    RequiredMCPServer(
                        name: name,
                        transport: .stdio(
                            command: command,
                            arguments: entry["args"] as? [String] ?? [],
                            environment: entry["env"] as? [String: String] ?? [:])))
            case (nil, let url?):
                var ignored: [String] = []
                guard let url = webURL(url, &ignored) else {
                    problems.append("\(name)'s url isn't an http or https URL; skipped")
                    continue
                }
                servers.append(
                    RequiredMCPServer(
                        name: name, transport: .http(url: url, headers: entry["headers"] as? [String: String] ?? [:])))
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
            endpoints.append(
                TelemetryEndpoint(
                    url: url,
                    headers: entry["headers"] as? [String: String] ?? [:],
                    attributes: entry["attributes"] as? [String: String] ?? [:]))
        }
        return endpoints
    }
}
