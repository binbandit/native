import Foundation

/// A random id for this installation, so events can be counted per installation without knowing
/// whose it is. Never linked to an account; the user can replace it any time.
public struct TelemetryInstallationID: @unchecked Sendable {
    // UserDefaults is thread-safe; it just isn't annotated Sendable on every SDK.
    public static let key = "telemetry.installationID"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var current: UUID {
        if let stored = defaults.string(forKey: Self.key).flatMap(UUID.init(uuidString:)) {
            return stored
        }
        return rotate()
    }

    @discardableResult
    public func rotate() -> UUID {
        let id = UUID()
        defaults.set(id.uuidString, forKey: Self.key)
        return id
    }
}
