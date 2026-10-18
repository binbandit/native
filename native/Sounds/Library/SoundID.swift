import Foundation

/// A sound the user can pick, stored in preferences by its raw value.
nonisolated enum SoundID: Hashable, Sendable {
    case native(NativeChime)
    /// One of the reference app's sounds by its own id (`"default"`, `"choo-choo"`), played from the user's
    /// local copy.
    case conductor(String)
    case custom(UUID)

    static let `default` = SoundID.native(.chime)
}

extension SoundID: RawRepresentable {
    init?(rawValue: String) {
        let parts = rawValue.split(separator: ":", maxSplits: 1).map(String.init)
        let value = parts.count == 2 ? parts[1] : nil
        switch (parts.first, value) {
        case ("native", let name?):
            guard let chime = NativeChime(rawValue: name) else { return nil }
            self = .native(chime)
        case ("conductor", let name?):
            self = .conductor(name)
        case ("custom", let uuid?):
            guard let id = UUID(uuidString: uuid) else { return nil }
            self = .custom(id)
        default:
            return nil
        }
    }

    var rawValue: String {
        switch self {
        case .native(let chime): "native:\(chime.rawValue)"
        case .conductor(let name): "conductor:\(name)"
        case .custom(let id): "custom:\(id.uuidString)"
        }
    }
}
