import Foundation

/// A sound the user can pick, stored in preferences by its raw value. A stored value Native can't
/// read (one from another version, say) falls back to the trigger's default.
nonisolated enum SoundID: Hashable, Sendable {
    case native(NativeChime)
    /// A file in the user's sounds folder, by its file name, so a choice follows the file when the
    /// user points the setting at another copy of the folder.
    case folder(String)
    case custom(UUID)
}

extension SoundID: RawRepresentable {
    init?(rawValue: String) {
        let parts = rawValue.split(separator: ":", maxSplits: 1).map(String.init)
        let value = parts.count == 2 ? parts[1] : nil
        switch (parts.first, value) {
        case ("native", let name?):
            guard let chime = NativeChime(rawValue: name) else { return nil }
            self = .native(chime)
        case ("folder", let name?):
            self = .folder(name)
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
        case .folder(let name): "folder:\(name)"
        case .custom(let id): "custom:\(id.uuidString)"
        }
    }
}
