/// The slash command being typed: the draft while it's a bare "/name", before any argument.
struct SlashCommandQuery: Equatable {
    /// What's typed after the slash.
    let text: String

    init?(draft: String) {
        guard draft.hasPrefix("/"), !draft.contains(where: \.isWhitespace) else { return nil }
        text = String(draft.dropFirst())
    }

    /// The draft once `command` is inserted, ready for its argument.
    static func draft(inserting command: ComposerSlashCommand) -> String {
        "/\(command.name) "
    }

    /// The commands matching the query, as Factory ranks them: exact names first, then prefixes,
    /// then word prefixes, then names containing the query, keeping the agent's order within each.
    func matches(in commands: [ComposerSlashCommand]) -> [ComposerSlashCommand] {
        let query = text.lowercased()
        guard !query.isEmpty else { return commands }
        return commands.enumerated()
            .compactMap { offset, command -> (rank: Int, offset: Int, command: ComposerSlashCommand)? in
                let name = command.name.lowercased()
                let words = name.split { !$0.isLetter && !$0.isNumber }
                let rank: Int? =
                    if name == query { 0 }
                    else if name.hasPrefix(query) { 1 }
                    else if words.contains(where: { $0.hasPrefix(query) }) { 2 }
                    else if name.contains(query) { 3 }
                    else { nil }
                return rank.map { ($0, offset, command) }
            }
            .sorted { ($0.rank, $0.offset) < ($1.rank, $1.offset) }
            .map(\.command)
    }
}
