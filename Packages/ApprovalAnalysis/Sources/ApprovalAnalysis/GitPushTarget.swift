import Foundation

/// Where a literal `git push` sends commits, read only from its own words: the remote as typed and
/// the branch it changes there. Several refspecs, `--all`, `--tags` and `--mirror` describe more
/// than one branch, so they get no target.
public struct GitPushTarget: Equatable, Sendable {
    /// A remote name or URL; nil leaves the destination to Git configuration.
    public let remote: String?
    /// The local commit or branch pushed; nil pushes the current branch.
    public let source: String?
    /// The ref it changes on the remote; nil leaves ref selection to Git configuration.
    public let branch: String?
    public let deletes: Bool
    /// Replaces the remote branch even where it has commits the pushed one doesn't.
    public let forces: Bool
    /// The characters naming the remote and branch, annotated as one part.
    public let range: Range<Int>?

    init?(match: CommandKnowledgeMatch) {
        guard match.executables.contains("git"), match.rule.words == ["push"] else { return nil }
        let names = Set(match.options.flatMap(\.option.names))
        guard names.isDisjoint(with: ["--all", "--tags", "--mirror"]), match.operands.count <= 2 else { return nil }
        let operands = match.operands
        remote = operands.first?.value
        range = operands.first.map { first in first.range.lowerBound..<(operands.last ?? first).range.upperBound }
        var refspec = operands.count == 2 ? operands[1].value : nil
        let plus = refspec?.hasPrefix("+") == true
        if plus { refspec?.removeFirst() }
        forces = plus || !names.isDisjoint(with: ["-f", "--force", "--force-with-lease"])
        if let spec = refspec, let colon = spec.firstIndex(of: ":") {
            let destination = String(spec[spec.index(after: colon)...])
            source = colon == spec.startIndex ? nil : String(spec[..<colon])
            branch = Self.short(destination)
            deletes = colon == spec.startIndex || names.contains("--delete")
        } else {
            source = refspec
            branch = names.contains("--delete") ? refspec.map(Self.short) : nil
            deletes = names.contains("--delete")
        }
        guard branch?.isEmpty != true else { return nil }
    }

    /// "overwrite main on github.com"; `place` names the remote better than its name when known.
    public func headline(
        place: String?, destination: String? = nil, marking: (String) -> String = { $0 }
    ) -> String {
        let place = place ?? remote ?? "its remote"
        let branch = destination ?? branch
        if deletes { return "delete \(branch.map(marking) ?? "refs") on \(place)" }
        if forces { return "overwrite \(branch.map(marking) ?? "refs") on \(place)" }
        return "push \(branch.map(marking) ?? "commits") to \(place)"
    }

    /// The annotation before the remote has been read: "main on origin".
    var description: String {
        guard let remote else { return "destinations selected by Git" }
        return branch.map { "\($0) on \(remote)" } ?? "refs selected by Git on \(remote)"
    }

    private static func short(_ ref: String) -> String {
        ref.hasPrefix("refs/heads/") ? String(ref.dropFirst("refs/heads/".count)) : ref
    }
}
