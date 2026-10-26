import Foundation

/// What Native asks Codex to leave out of every session, as the `CODEX_CONFIG` JSON its ACP adapter
/// (codex-acp 2.2.2) merges into each session's config. Every feature adds to one value, so MCP
/// servers and skills always land in the same document.
///
/// Known limit: when a session brings MCP servers of its own (Native's orchestration server, say),
/// the adapter replaces the whole `mcp_servers` table with them, and the dotted
/// `mcp_servers.<name>.enabled` keys only win when they happen to apply after it.
/// docs/agent-session-overrides.md has the details and the adapter change that fixes it.
public struct CodexConfigOverrides: Hashable, Sendable {
    /// MCP servers by the name Codex gives them, and only those its own config defines: any other
    /// name becomes an entry with no command, and Codex then fails every new session ("Internal
    /// error"). `MCPLibrary.launchPolicy` names only an agent's configured servers for this reason.
    public var disabledMCPServers: Set<String>
    /// Skills by the path of their SKILL.md.
    public private(set) var disabledSkillFiles: Set<String>

    public init(disabledMCPServers: Set<String> = [], disabledSkills: some Sequence<String> = [String]()) {
        self.disabledMCPServers = disabledMCPServers
        self.disabledSkillFiles = []
        disabledSkills.forEach { disableSkill(at: $0) }
    }

    /// A skill by its folder or its SKILL.md; Codex matches `skills.config` entries by the file.
    public mutating func disableSkill(at path: String) {
        disabledSkillFiles.insert(path.hasSuffix("/SKILL.md") ? path : path + "/SKILL.md")
    }

    /// Produces a candidate configuration for fixture qualification. This does not qualify or
    /// authorize a launch. Only the host can admit a private route.
    public func environment(
        for route: AgentPrivateRoute, inheriting environment: [String: String] = [:]
    ) throws
        -> [String: String]
    {
        guard route.identity.declarationID == AgentNetworkCapabilities.codexCandidate.declarationID,
            route.identity.cliVersion == AgentNetworkCapabilities.codexCandidate.cliVersion,
            route.identity.adapterVersion == AgentNetworkCapabilities.codexCandidate.adapterVersion
        else { throw AgentRouteFailure.unqualified }
        guard let origin = URLComponents(string: route.origin),
            origin.string == route.origin, origin.user == nil, origin.password == nil,
            origin.query == nil, origin.fragment == nil, origin.path.isEmpty || origin.path == "/",
            let host = origin.host, !host.isEmpty, Self.isProviderHost(host),
            origin.percentEncodedHost?.contains("%") == false,
            !route.origin.contains("\\"), !route.origin.contains(where: { $0.isWhitespace }),
            !route.origin.trimmingCharacters(in: CharacterSet(charactersIn: "/")).hasSuffix(":"),
            origin.port.map({ (1...65535).contains($0) }) ?? true,
            origin.scheme == "https" || (origin.scheme == "http" && host == "127.0.0.1"),
            !route.model.isEmpty, !route.model.contains(where: { $0.isWhitespace })
        else { throw AgentRouteFailure.invalidRoute }
        guard case .runtimeEnvironment(let variable) = route.authentication,
            variable.hasPrefix("NATIVE_PROVIDER_"), variable.count > "NATIVE_PROVIDER_".count,
            variable.allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber || $0 == "_") }),
            route.proxyOrigin == nil, !route.bypassProxy, route.customCAFile == nil
        else { throw AgentRouteFailure.unsupportedControl }
        // Never merge arbitrary provider tables or inherited credentials/settings. A caller supplies
        // the operator's runtime key separately, after admission, without persisting it in a spec.
        guard environment.isEmpty else { throw AgentRouteFailure.conflictingConfiguration }
        guard case .object(var config) = self.config else { throw AgentRouteFailure.invalidRoute }
        config["model"] = .string(route.model)
        config["model_provider"] = .string("native_private")
        config["model_providers"] = .object([
            "native_private": .object([
                "name": .string("Native private provider"),
                "base_url": .string(route.origin.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/v1"),
                "wire_api": .string("responses"), "env_key": .string(variable),
                "requires_openai_auth": .bool(false), "supports_websockets": .bool(false),
                "request_max_retries": .number(0), "stream_max_retries": .number(0),
            ])
        ])
        config["web_search"] = .string("disabled")
        config["check_for_update_on_startup"] = .bool(false)
        config["analytics"] = .object(["enabled": .bool(false)])
        config["feedback"] = .object(["enabled": .bool(false)])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return [
            "CODEX_CONFIG": String(decoding: try encoder.encode(JSONValue.object(config)), as: UTF8.self),
            "MODEL_PROVIDER": "native_private",
        ]
    }

    private static func isProviderHost(_ host: String) -> Bool {
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard host.count <= 253,
            labels.allSatisfy({ label in
                !label.isEmpty && label.count <= 63 && label.first != "-" && label.last != "-"
                    && label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
            })
        else { return false }
        if labels.last?.allSatisfy({ $0.isNumber }) == true || labels.contains(where: { $0.hasPrefix("0x") }) {
            return labels.count == 4
                && labels.allSatisfy { label in
                    guard let value = UInt8(label) else { return false }
                    return String(value) == label
                }
        }
        return true
    }

    public var isEmpty: Bool {
        disabledMCPServers.isEmpty && disabledSkillFiles.isEmpty
    }

    /// The document. Servers are switched off twice: the nested table holds once the adapter merges
    /// a session's servers into it, and the dotted keys cover today's adapter as far as it allows.
    public var config: JSONValue {
        var config: [String: JSONValue] = [:]
        let servers = disabledMCPServers.sorted()
        if !servers.isEmpty {
            let off = JSONValue.object(["enabled": .bool(false)])
            config["mcp_servers"] = .object(Dictionary(uniqueKeysWithValues: servers.map { ($0, off) }))
            for server in servers { config["mcp_servers.\(server).enabled"] = .bool(false) }
        }
        let skills = disabledSkillFiles.sorted()
        if !skills.isEmpty {
            // Hidden from the model; the adapter's `$skill` command list still shows them, since it
            // builds that from `skills/list` (verified with gpt-6.1-sol).
            let entries = skills.map { JSONValue.object(["path": .string($0), "enabled": .bool(false)]) }
            config["skills"] = .object(["config": .array(entries)])
        }
        return .object(config)
    }

    /// The agent process's environment for these overrides; empty when there are none.
    public var environment: [String: String] {
        guard !isEmpty else { return [:] }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(config) else { return [:] }
        return ["CODEX_CONFIG": String(decoding: data, as: UTF8.self)]
    }
}
