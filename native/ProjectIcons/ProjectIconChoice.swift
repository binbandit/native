import Foundation

/// What the user chose to lead a project in the sidebar. Automatic uses the icon Native finds in the
/// project (its favicon or app icon), falling back to its initial.
nonisolated enum ProjectIconChoice: Codable, Hashable, Sendable {
    case automatic
    /// The name's first letter on a tile, even when an icon was found.
    case initial
    case emoji(String)
    /// An SF Symbol name.
    case symbol(String)
    /// An image the user picked, kept by `ProjectIconStore`.
    case image
}
