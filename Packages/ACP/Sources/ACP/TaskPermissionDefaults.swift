import Foundation

/// Shared task defaults, independent of provider. Existing explicit choices migrate once, using
/// the strictest saved choice if several providers disagreed. Missing choices start at full access.
public enum TaskPermissionDefaults {
    public static let key = "permissions.defaultMode"

    public static func key(project: String?) -> String {
        project.map { "projectDefaults.\($0).permissionMode" } ?? key
    }

    public static func migrate(in defaults: UserDefaults) {
        let saved = defaults.dictionaryRepresentation()
        var scopes: [String: [TaskPermissionMode]] = [:]
        for (key, value) in saved where key.hasSuffix(".permissions") {
            guard let value = value as? String, !value.isEmpty else { continue }
            let mode = TaskPermissionMode.migrating(value) ?? .askFirst
            let parts = key.split(separator: ".")
            let destination: String
            if parts.first == "agentDefaults" {
                destination = Self.key
            } else if parts.first == "projectDefaults", parts.count >= 4 {
                destination = Self.key(project: String(parts[1]))
            } else {
                continue
            }
            scopes[destination, default: []].append(mode)
        }
        for (key, modes) in scopes where defaults.string(forKey: key) == nil {
            defaults.set(modes.min { $0.rank < $1.rank }?.rawValue, forKey: key)
        }
        // Removing migrated keys prevents a reset from reviving a provider-specific choice.
        for key in saved.keys
        where key.hasSuffix(".permissions")
            && (key.hasPrefix("agentDefaults.") || key.hasPrefix("projectDefaults."))
        {
            defaults.removeObject(forKey: key)
        }
    }

    public static func value(project: String? = nil, defaults: UserDefaults = .standard) -> TaskPermissionMode {
        migrate(in: defaults)
        if let saved = defaults.string(forKey: key(project: project)) {
            return TaskPermissionMode.migrating(saved) ?? .askFirst
        }
        if let saved = defaults.string(forKey: key) {
            return TaskPermissionMode.migrating(saved) ?? .askFirst
        }
        return .fullAccess
    }
}
