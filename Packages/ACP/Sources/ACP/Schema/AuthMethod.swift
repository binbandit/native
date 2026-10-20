import Foundation

/// One way to sign an agent in: from the `authMethods` of its `initialize` response, or declared by
/// its plugin for a method the agent accepts without advertising it (Claude Code reads
/// `ANTHROPIC_API_KEY` but its adapter lists no methods). Every shape ACP has used decodes:
///
/// - No `type`, or `"agent"`: `authenticate` signs in. The agent may open a browser where it runs,
///   or ask the client to send the user to a page with a code (a URL elicitation, Codex's device
///   code).
/// - An agent method with `_meta["api-key"]`: `authenticate` takes the key in its own
///   `_meta["api-key"].apiKey` (codex-acp).
/// - `"env_var"`: the client starts the agent with these variables set, named by `vars` or, in the
///   first draft, `varName`. ACP dropped it in 2026-07 because it assumes the client launches the
///   agent; Native's host does, so plugins still declare methods this way.
/// - `"terminal"`, or `_meta["terminal-auth"]`: a command the user runs in a terminal.
/// - `"_native/link"`, Native's own (ACP leaves `_` types to implementations): an agent method that
///   sends the user to a page with a code, which agents only offer to clients that open links (a
///   plugin declares it; see `Kind.link`).
///
/// Any other `type` is `unknown`, kept with its JSON: encoding a method gives back what came in.
public struct AuthMethod: Codable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// `authenticate` does it, however the agent signs in.
        case agent
        /// `authenticate` with an API key in its `_meta` (`AuthenticateRequest.apiKey`). `provider`
        /// says whose key it is ("openai").
        case apiKey(provider: String?)
        /// Start the agent with these variables set; `authenticate` isn't needed for it.
        case environment([Variable])
        /// `authenticate` sends the user to a page with a code to enter, from any device: a URL
        /// elicitation scoped to the request (Codex's device code). Agents offer these only to
        /// clients that advertise URL elicitations, so Native's host starts the agent for it.
        case link
        /// Only works in a terminal, so `authenticate` can't do it.
        case terminal(Terminal)
        /// A `type` this build doesn't know. Offer it as unsupported rather than guessing.
        case unknown(type: String)
    }

    /// A sign-in that only works in a terminal: the client runs a command in a terminal for the user.
    public enum Terminal: Hashable, Sendable {
        /// ACP's `"type": "terminal"`: run the agent's own command with these arguments.
        case agent(arguments: [String])
        /// Zed's `_meta["terminal-auth"]`: run this command.
        case command(String, arguments: [String])
    }

    /// One variable of an `environment` method.
    public struct Variable: Codable, Hashable, Sendable {
        /// `ANTHROPIC_API_KEY`.
        public var name: String
        /// What to call it in a form ("API key").
        public var label: String?
        /// A key or token: typed into a secure field, never shown again.
        public var isSecret: Bool
        public var isOptional: Bool

        public init(name: String, label: String? = nil, isSecret: Bool = true, isOptional: Bool = false) {
            self.name = name
            self.label = label
            self.isSecret = isSecret
            self.isOptional = isOptional
        }

        private enum CodingKeys: String, CodingKey {
            case name, label, secret, optional
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            label = try container.decodeIfPresent(String.self, forKey: .label)
            isSecret = try container.decodeIfPresent(Bool.self, forKey: .secret) ?? true
            isOptional = try container.decodeIfPresent(Bool.self, forKey: .optional) ?? false
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encodeIfPresent(label, forKey: .label)
            try container.encode(isSecret, forKey: .secret)
            try container.encode(isOptional, forKey: .optional)
        }
    }

    public var id: String
    public var name: String
    public var description: String?
    public var kind: Kind
    /// Where the user gets the key or token (`link` on the wire).
    public var credentialsPage: URL?
    /// The method as the agent or plugin wrote it, re-encoded verbatim. Not part of equality.
    private var json: JSONValue

    public init(
        id: String, name: String, description: String? = nil, kind: Kind = .agent, credentialsPage: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.kind = kind
        self.credentialsPage = credentialsPage
        json = Self.json(
            id: id, name: name, description: description, kind: kind, credentialsPage: credentialsPage)
    }

    public init(id: String, name: String, description: String? = nil, terminal: Terminal?) {
        self.init(id: id, name: name, description: description, kind: terminal.map(Kind.terminal) ?? .agent)
    }

    /// Set when the method only works in a terminal.
    public var terminal: Terminal? {
        if case .terminal(let terminal) = kind { terminal } else { nil }
    }

    /// Whether signing in with it takes one key or token the user types: an `apiKey` method, or an
    /// `environment` one with exactly one required variable (`secretVariable`).
    public var takesSecret: Bool {
        switch kind {
        case .apiKey: true
        case .environment: secretVariable != nil
        case .agent, .link, .terminal, .unknown: false
        }
    }

    /// The variable an `environment` method's one key goes in, when it needs exactly one.
    public var secretVariable: Variable? {
        guard case .environment(let variables) = kind else { return nil }
        let required = variables.filter { !$0.isOptional }
        return required.count == 1 ? required.first : nil
    }

    public static func == (lhs: AuthMethod, rhs: AuthMethod) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.description == rhs.description && lhs.kind == rhs.kind
            && lhs.credentialsPage == rhs.credentialsPage
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(kind)
    }

    // MARK: - Coding

    public init(from decoder: any Decoder) throws {
        let json = try JSONValue(from: decoder)
        guard let id = json["id"]?.stringValue, let name = json["name"]?.stringValue else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath, debugDescription: "An auth method needs an id and a name."))
        }
        self.id = id
        self.name = name
        self.json = json
        description = json["description"]?.stringValue
        credentialsPage = json["link"]?.stringValue.flatMap(URL.init(string:))
        kind = Self.kind(of: json)
    }

    public func encode(to encoder: any Encoder) throws {
        try json.encode(to: encoder)
    }

    private static func kind(of json: JSONValue) -> Kind {
        let meta = json["_meta"]
        if let terminalAuth = meta?["terminal-auth"], let command = terminalAuth["command"]?.stringValue {
            return .terminal(.command(command, arguments: strings(terminalAuth["args"])))
        }
        switch json["type"]?.stringValue {
        case nil, "agent":
            guard let apiKey = meta?["api-key"], case .object = apiKey else { return .agent }
            return .apiKey(provider: apiKey["provider"]?.stringValue)
        case "terminal":
            return .terminal(.agent(arguments: strings(json["args"])))
        case Self.linkType:
            return .link
        case "env_var":
            if case .array(let variables) = json["vars"] {
                return .environment(variables.compactMap(variable))
            }
            return .environment(json["varName"]?.stringValue.map { [Variable(name: $0)] } ?? [])
        case let other?:
            return .unknown(type: other)
        }
    }

    private static func variable(_ json: JSONValue) -> Variable? {
        guard let name = json["name"]?.stringValue else { return nil }
        let flag = { (key: String) -> Bool? in if case .bool(let value)? = json[key] { value } else { nil } }
        return Variable(
            name: name, label: json["label"]?.stringValue, isSecret: flag("secret") ?? true,
            isOptional: flag("optional") ?? false)
    }

    private static let linkType = "_native/link"

    private static func strings(_ value: JSONValue?) -> [String] {
        guard case .array(let values) = value else { return [] }
        return values.compactMap(\.stringValue)
    }

    /// What a method made in code looks like on the wire, in the shapes `kind(of:)` reads.
    private static func json(
        id: String, name: String, description: String?, kind: Kind, credentialsPage: URL?
    ) -> JSONValue {
        var object: [String: JSONValue] = ["id": .string(id), "name": .string(name)]
        object["description"] = description.map(JSONValue.string)
        object["link"] = credentialsPage.map { .string($0.absoluteString) }
        let strings = { (values: [String]) in JSONValue.array(values.map(JSONValue.string)) }
        switch kind {
        case .agent:
            break
        case .apiKey(let provider):
            object["_meta"] = .object(["api-key": .object(provider.map { ["provider": .string($0)] } ?? [:])])
        case .environment(let variables):
            object["type"] = .string("env_var")
            object["vars"] = .array(
                variables.map { variable in
                    var json: [String: JSONValue] = [
                        "name": .string(variable.name), "secret": .bool(variable.isSecret),
                        "optional": .bool(variable.isOptional),
                    ]
                    json["label"] = variable.label.map(JSONValue.string)
                    return .object(json)
                })
        case .link:
            object["type"] = .string(linkType)
        case .terminal(.agent(let arguments)):
            object["type"] = .string("terminal")
            object["args"] = strings(arguments)
        case .terminal(.command(let command, let arguments)):
            object["_meta"] = .object([
                "terminal-auth": .object(["command": .string(command), "args": strings(arguments)])
            ])
        case .unknown(let type):
            object["type"] = .string(type)
        }
        return .object(object)
    }
}
