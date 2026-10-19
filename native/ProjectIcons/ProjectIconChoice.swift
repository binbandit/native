import Foundation

/// What the user chose to lead a project in the sidebar. Automatic uses the icon Native finds in the
/// project (its favicon or app icon), falling back to its initial.
nonisolated enum ProjectIconChoice: Codable, Hashable, Sendable {
    case automatic
    /// One of the icons found in the project, by its path relative to the project's folder. It's
    /// read again each launch, so it follows changes to the file.
    case file(String)
    /// The name's first letter on a tile, even when an icon was found.
    case initial
    case emoji(String)
    /// An SF Symbol name.
    case symbol(String)
    /// An image the user picked, kept by `ProjectIconStore`.
    case image
}

extension ProjectIconChoice {
    /// Whether the icon is read from a file in the project: the one found, or the one chosen.
    var readsProjectFile: Bool {
        switch self {
        case .automatic, .file: true
        case .initial, .emoji, .symbol, .image: false
        }
    }
}
