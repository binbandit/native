import ACP

/// What the list above the composer offers right now: slash commands for a bare "/name", or files
/// for an `@` mention at the cursor.
enum ComposerSuggestions {
    case commands([ComposerSlashCommand])
    case files([String], query: FileMentionQuery)

    var count: Int {
        switch self {
        case .commands(let commands): commands.count
        case .files(let files, _): files.count
        }
    }
}
