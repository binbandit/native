import Foundation

/// Where the terminals' settings come from right now, for Settings ▸ Terminal and the panel.
enum TerminalConfigStatus: Equatable {
    /// Native's own settings.
    case native
    /// The user's Ghostty config, read from these files in load order.
    case ghostty(files: [URL])
    /// "Use my Ghostty settings" is on but there's no config at any of these paths, so Native's
    /// settings apply.
    case ghosttyNotFound(searched: [URL])
    /// The config has problems, each `path:line: message` as libghostty reports it. Native's
    /// settings apply until they're fixed.
    case ghosttyInvalid(files: [URL], diagnostics: [String])
    /// Ghostty settings were asked for, but the terminal engine hasn't started yet to read them.
    case ghosttyPending

    /// The user's config files involved, for watching and for showing where settings come from.
    var files: [URL] {
        switch self {
        case .ghostty(let files), .ghosttyInvalid(let files, _): files
        case .ghosttyNotFound(let searched): searched
        case .native, .ghosttyPending: []
        }
    }
}
