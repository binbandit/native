import ACP
import Foundation

/// Exact selections for a delegated session. Omitted permissions inherit a safe equivalent.
public struct TaskLaunchOptions: Codable, Hashable, Sendable {
    public var model: String?
    public var effort: String?
    public var permissions: String?
    /// An existing checkout on the same host. Native does not create a worktree here.
    public var checkout: String?

    public init(model: String? = nil, effort: String? = nil, permissions: String? = nil, checkout: String? = nil) {
        self.model = model
        self.effort = effort
        self.permissions = permissions
        self.checkout = checkout
    }
}

/// Admission uses advertised ACP settings and the existing semantic permission translator.
public enum TaskLaunchValidation {
    public struct Refusal: LocalizedError, Sendable {
        public let reason: String
        public init(_ reason: String) { self.reason = reason }
        public var errorDescription: String? { reason }
    }

    public static func checkout(_ requested: String?, inherited: URL) throws -> URL {
        guard let requested else { return inherited }
        guard requested.hasPrefix("/"), !requested.contains("\0") else {
            throw Refusal("Checkout must be an existing absolute directory on this host.")
        }
        let url = URL(filePath: requested, directoryHint: .isDirectory).resolvingSymlinksInPath()
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue else {
            throw Refusal("The requested checkout directory does not exist on this host. Create it before delegating.")
        }
        return url
    }

    public static func option(category: String, in options: [ConfigOption]) throws -> ConfigOption {
        let matches = options.filter { $0.category == category }
        guard matches.count == 1, let option = matches.first, case .select = option.kind else {
            throw Refusal("The agent does not advertise one selectable \(category) setting.")
        }
        return option
    }

    public static func exact(_ value: String, category: String, in options: [ConfigOption]) throws -> ConfigOption {
        let option = try option(category: category, in: options)
        guard case .select(_, let choices) = option.kind, choices.contains(where: { $0.value == value }) else {
            throw Refusal(
                "The agent does not offer \(category) value \"\(value)\". Use list_agents to inspect advertised settings."
            )
        }
        return option
    }

    public static func current(_ option: ConfigOption) -> String? {
        if case .select(let value, _) = option.kind { value } else { nil }
    }

    public static func permission(
        parent: [ConfigOption], child: [ConfigOption], requested: String?
    ) throws -> (ConfigOption, String) {
        let source = try option(category: "mode", in: parent)
        let target = try option(category: "mode", in: child)
        guard let ceiling = current(source), case .select(_, let choices) = target.kind else {
            throw Refusal(
                "Native cannot establish the parent's permissions. Ask the user to choose a known permission mode.")
        }
        let values = choices.map(\.value)
        let selection = selection(for: requested ?? ceiling, offered: values)
        guard let selection, selection.reason == .equivalent || (requested == nil && selection.reason == .stricter)
        else {
            throw Refusal("The agent does not offer a known safe equivalent for the requested permissions.")
        }
        let bounded = Self.selection(for: ceiling, offered: [selection.value])
        guard bounded?.reason == .equivalent || bounded?.reason == .stricter else {
            throw Refusal(
                "The child would have more permissions than its parent. Ask the user to change the parent's permissions first."
            )
        }
        // A plan restriction is not evidence of a read-only sandbox, or vice versa.
        if ceiling == "plan" || ceiling == "read-only" {
            guard selection.value == ceiling else {
                throw Refusal("The child cannot preserve the parent's \(ceiling) restriction.")
            }
        }
        return (target, selection.value)
    }

    private static func selection(
        for source: String, offered: [String]
    ) -> (value: String, reason: AgentModelPermissions.Reason)? {
        // Normalize Native's display vocabulary before translation. Its ordered picker fallback
        // cannot prove that risk review, trusted edits and workspace access are interchangeable.
        let values = offered.map(semanticValue)
        guard let selected = AgentModelPermissions.selection(for: semanticValue(source), offered: values),
            let index = values.firstIndex(of: selected.value)
        else { return nil }
        return (offered[index], selected.reason)
    }

    private static func semanticValue(_ value: String) -> String {
        switch value {
        case "ask-first": "default"
        case "accept-edits": "acceptEdits"
        case "full-access": "bypassPermissions"
        default: value
        }
    }

    public static func verify(_ id: String, value: String, in options: [ConfigOption]) throws {
        guard let actual = options.first(where: { $0.id == id }), current(actual) == value else {
            throw Refusal("The agent did not confirm \(id)=\(value). The child was not prompted.")
        }
    }
}
