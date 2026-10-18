/// Icon identity is separate from the update channel: local development builds keep their own artwork.
public enum AppIconVariant: String, CaseIterable, Sendable {
    case stable
    case beta
    case nightly
    case development = "dev"

    public var displayName: String {
        switch self {
        case .stable: "Native"
        case .beta: "Native Beta"
        case .nightly: "Native Nightly"
        case .development: "Native Dev"
        }
    }

    public func imageName(isDark: Bool) -> String {
        let name = self == .stable ? "original" : rawValue
        return "AppIcon-\(name)-\(isDark ? "dark" : "light")"
    }
}
