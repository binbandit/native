import ACP

extension SelectSetting {
    /// The model's name for the composer's chip: without the agent's "(recommended)" aside and, for
    /// the agent's default, the model it resolves to when the agent says (Claude Code's description
    /// is the bare model name then).
    var shortModelName: String {
        if value == Self.defaultValue, let resolved = current?.description, !resolved.isEmpty, !resolved.contains("·") {
            return resolved
        }
        let name = currentName.replacing(/\s*\(.*\)\s*$/, with: "")
        return name.isEmpty ? currentName : name
    }

    /// The choices whose name or description contains every word of `query`.
    func choices(matching query: String) -> [Choice] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return choices }
        return choices.filter { choice in
            let text = "\(choice.name) \(choice.description ?? "")".lowercased()
            return words.allSatisfy { text.contains($0) }
        }
    }
}
