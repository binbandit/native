import Foundation

/// Matches a whole literal argv against one documented grammar, never a familiar prefix alone.
struct CommandKnowledgeMatch {
    typealias Token = ApprovalCommandWords.Token
    struct MatchedOption {
        let range: Range<Int>
        let option: CommandKnowledge.Option
    }
    let rule: CommandKnowledge.Command
    let prefix: Range<Int>
    var options: [MatchedOption] = []
    var operands: [Token] = []
    var terminator: Range<Int>?

    init?(words: ApprovalCommandWords, knowledge: CommandKnowledge) {
        let tokens = words.tokens
        guard let first = tokens.first,
            let program = knowledge.programs.first(where: { $0.executables.contains(first.value) }),
            let rule = program.commands.sorted(by: { $0.words.count > $1.words.count }).first(where: {
                tokens.dropFirst().prefix($0.words.count).map(\.value) == $0.words
            })
        else { return nil }
        self.rule = rule
        prefix = first.range.lowerBound..<tokens[rule.words.count].range.upperBound
        var index = 1 + rule.words.count
        var ended = false
        while index < tokens.count {
            let token = tokens[index]
            if !ended && token.value == "--" {
                terminator = token.range
                ended = true
                index += 1
                continue
            }
            if !ended && token.value.hasPrefix("-") && token.value != "-" {
                guard let matched = Self.options(token.value, rule: rule) else { return nil }
                // One annotation per source token, including a cluster such as -rf.
                var range = token.range
                if matched.needsNext {
                    index += 1
                    guard index < tokens.count,
                        !tokens[index].value.hasPrefix("-") || tokens[index].value == "-"
                    else { return nil }
                    range = range.lowerBound..<tokens[index].range.upperBound
                }
                guard matched.options.count == 1 || !matched.options.contains(where: { $0.replacement != nil }) else {
                    return nil
                }
                let option = CommandKnowledge.Option(
                    names: matched.options.flatMap(\.names),
                    summary: matched.options.map(\.summary).joined(separator: "; "),
                    destructive: matched.options.contains(where: \.destructive), value: "none",
                    replacement: matched.options.first?.replacement, alternative: matched.options.first?.alternative)
                options.append(.init(range: range, option: option))
            } else {
                operands.append(token)
                if rule.optionsBeforeOperands == true { ended = true }
            }
            index += 1
        }
        guard operands.count >= rule.operands.minimum,
            rule.operands.maximum.map({ operands.count <= $0 }) ?? true
        else { return nil }
    }

    private static func options(
        _ text: String, rule: CommandKnowledge.Command
    ) -> (options: [CommandKnowledge.Option], needsNext: Bool)? {
        if let exact = rule.options.first(where: { $0.names.contains(text) }) {
            return ([exact], exact.value != "none")
        }
        if let equals = text.firstIndex(of: "="), text.hasPrefix("--"),
            let option = rule.options.first(where: {
                $0.value == "attached" && $0.names.contains(String(text[..<equals]))
            }),
            !text[text.index(after: equals)...].isEmpty
        {
            return ([option], false)
        }
        guard !text.hasPrefix("--"), text.count > 2 else { return nil }
        var matched: [CommandKnowledge.Option] = []
        let chars = Array(text.dropFirst())
        for (index, char) in chars.enumerated() {
            guard let option = rule.options.first(where: { $0.names.contains("-\(char)") }),
                index == 0 || rule.shortClusters == true
            else { return nil }
            matched.append(option)
            if option.value != "none" {
                if index == chars.count - 1 { return (matched, true) }
                return option.value == "attached" ? (matched, false) : nil
            }
        }
        return rule.shortClusters == true ? (matched, false) : nil
    }

    static func isInside(_ path: String, root: String) -> Bool {
        let path = URL(filePath: path).standardizedFileURL.path
        let root = URL(filePath: root).standardizedFileURL.path
        return path == root || path.hasPrefix(root == "/" ? "/" : root + "/")
    }

    static func pathFacts(
        _ token: Token, cwd: String, root: String, home: String?, knowledge: CommandKnowledge
    ) -> (scope: String, location: String) {
        var path = token.value
        if path.hasPrefix("~") && token.expandsHome {
            guard path.hasPrefix("~/"), let home else {
                return ("home directory unknown", "path; contents not inspected")
            }
            path = home + path.dropFirst()
        }
        if !path.hasPrefix("/") { path = cwd + "/" + path }
        path = URL(filePath: path).standardizedFileURL.path
        let location = knowledge.locations.first { location in
            switch location.kind {
            case "component": return path.split(separator: "/").contains(Substring(location.path))
            case "homePrefix":
                guard let home else { return false }
                return isInside(path, root: home + "/" + location.path)
            default: return false
            }
        }
        return (
            isInside(path, root: root) ? "lexically inside the worktree" : "lexically outside the worktree",
            location?.summary ?? "path; contents not inspected"
        )
    }
}
