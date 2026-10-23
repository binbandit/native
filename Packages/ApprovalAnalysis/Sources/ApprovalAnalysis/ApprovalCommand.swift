import Foundation

/// A conservative description, never an authorization or a shell interpreter. No filesystem or
/// network access: observations about files and remote commits must come from a separate inspector.
public struct ApprovalCommand: Equatable, Sendable {
    public enum Risk: Equatable, Sendable {
        case routine, irreversible, unknown
    }

    public struct Part: Equatable, Sendable, Identifiable {
        public let range: Range<Int>
        public let explanation: String
        public let destructive: Bool
        public var id: Int { range.lowerBound }
    }

    public let command: String
    public let risk: Risk
    public let action: String
    public let reason: String
    public let consequence: String
    public let parts: [Part]
    public let suggestedCommand: String?

    public init(
        command: String, workingDirectory: String, worktreeDirectory: String? = nil, homeDirectory: String? = nil
    ) {
        let directory = URL(filePath: workingDirectory).standardizedFileURL.path
        let worktree = URL(filePath: worktreeDirectory ?? workingDirectory).standardizedFileURL.path
        let startsInside = directory == worktree || directory.hasPrefix(worktree + "/")
        let words = ApprovalCommandWords(command)
        let executable = words?.tokens.first.map { URL(filePath: $0.value).lastPathComponent }
        let unknown = Self(
            command: command, risk: .unknown, action: executable.map { "run \($0)" } ?? "run this command",
            reason: startsInside
                ? "Requested from this task's worktree." : "Requested from a folder outside the worktree.",
            consequence:
                "Native can't describe this command, so it makes no claims about its effects or whether they can be undone.",
            parts: [], suggestedCommand: nil)
        guard let words, let program = words.tokens.first else {
            self = unknown
            return
        }
        switch program.value {
        case "git", "/usr/bin/git":
            self = Self.push(words, command: command) ?? unknown
        case "rm", "/bin/rm":
            self =
                Self.remove(
                    words, command: command, cwd: workingDirectory, worktree: worktreeDirectory ?? workingDirectory,
                    home: homeDirectory) ?? unknown
        default:
            self = unknown
        }
    }

    private init(
        command: String, risk: Risk, action: String, reason: String, consequence: String,
        parts: [Part], suggestedCommand: String?
    ) {
        self.command = command
        self.risk = risk
        self.action = action
        self.reason = reason
        self.consequence = consequence
        self.parts = parts
        self.suggestedCommand = suggestedCommand
    }

    private static func push(_ words: ApprovalCommandWords, command: String) -> Self? {
        let tokens = words.tokens
        guard tokens.count >= 4, tokens[1].value == "push" else { return nil }
        let flags = tokens.dropFirst(2).filter { $0.value.hasPrefix("-") }
        guard flags.allSatisfy({ ["--force", "-f", "--force-with-lease"].contains($0.value) }) else { return nil }
        let destinations = tokens.dropFirst(2).filter { !$0.value.hasPrefix("-") }
        guard destinations.count == 2 else { return nil }
        let remote = destinations[destinations.startIndex]
        let branch = destinations[destinations.startIndex + 1]
        guard !remote.value.hasPrefix("-"), !branch.value.hasPrefix("-"),
            !branch.value.contains(":"), !branch.value.hasPrefix("+")
        else { return nil }
        let force = flags.filter { $0.value == "--force" || $0.value == "-f" }
        let lease = flags.contains { $0.value == "--force-with-lease" }
        // A lease can still replace history. It only checks the expected remote tip.
        let rewrites = !force.isEmpty || lease
        var parts = [
            Part(
                range: tokens[0].range.lowerBound..<tokens[1].range.upperBound,
                explanation: "send your commits", destructive: false)
        ]
        parts += flags.map {
            part(
                $0,
                $0.value == "--force-with-lease"
                    ? "replace history only if the remote tip matches the expected commit"
                    : "replace the branch there, even where it has commits yours doesn't", destructive: true)
        }
        let between = String(Array(command)[remote.range.upperBound..<branch.range.lowerBound])
        if between.allSatisfy(\.isWhitespace) {
            parts.append(
                Part(
                    range: remote.range.lowerBound..<branch.range.upperBound,
                    explanation:
                        "\(branch.value) on \(remote.value) · outside the worktree · remote commits not inspected",
                    destructive: false))
        } else {
            parts.append(part(remote, "remote: \(remote.value) · outside the worktree"))
            parts.append(part(branch, "branch: \(branch.value) · remote commits not inspected"))
        }
        var suggested: String?
        if !force.isEmpty {
            var characters = Array(command)
            // A remaining force flag overrides the lease, even if the command already has one.
            for flag in force.reversed() {
                characters.replaceSubrange(flag.range, with: Array("--force-with-lease"))
            }
            suggested = String(characters)
        }
        return Self(
            command: command, risk: rewrites ? .irreversible : .routine,
            action: "\(rewrites ? "overwrite" : "push") \(branch.value) on \(remote.value)",
            reason: "It reaches a remote outside the worktree.",
            consequence: rewrites
                ? "Can't be undone from here. Recovery may need other clones or reflogs."
                : "Publishes commits to the remote. Native can't undo this push from here.",
            parts: parts.sorted { $0.range.lowerBound < $1.range.lowerBound }, suggestedCommand: suggested)
    }

    private static func remove(
        _ words: ApprovalCommandWords, command: String, cwd: String, worktree: String, home: String?
    ) -> Self? {
        let tokens = words.tokens
        let flags = tokens.dropFirst().prefix { $0.value.hasPrefix("-") }
        guard flags.allSatisfy({ ["-r", "-R", "-f", "-rf", "-fr", "-Rf", "-fR", "--"].contains($0.value) }),
            flags.filter({ $0.value == "--" }).count <= 1,
            !flags.contains(where: { $0.value == "--" }) || flags.last?.value == "--"
        else { return nil }
        let paths = tokens.dropFirst(1 + flags.count)
        guard !paths.isEmpty, !paths.contains(where: { $0.value.hasPrefix("-") }) else { return nil }
        var allCaches = true
        var outside = false
        var parts = [part(tokens[0], "delete")]
        parts += flags.map {
            part(
                $0,
                $0.value == "--"
                    ? "the remaining arguments are paths"
                    : "\($0.value.contains("r") || $0.value.contains("R") ? "include folders and their contents" : "delete files")\($0.value.contains("f") ? ", without asking per file" : "")"
            )
        }
        let root = URL(filePath: worktree).standardizedFileURL.path
        let directory = URL(filePath: cwd).standardizedFileURL.path
        for path in paths {
            let expanded: String
            if path.value.hasPrefix("~/"), path.expandsHome, let home {
                expanded = home + String(path.value.dropFirst())
            } else if path.value.hasPrefix("~") {
                return nil
            } else {
                expanded = path.value.hasPrefix("/") ? path.value : directory + "/" + path.value
            }
            let normalized = URL(filePath: expanded).standardizedFileURL.path
            let isOutside = normalized != root && !normalized.hasPrefix(root + "/")
            outside = outside || isOutside
            let cacheRoot = home.map {
                URL(filePath: $0 + "/Library/Developer/Xcode/DerivedData").standardizedFileURL.path
            }
            let isCache = cacheRoot.map { normalized.hasPrefix($0 + "/") && normalized != $0 } ?? false
            allCaches = allCaches && isCache
            parts.append(
                part(
                    path,
                    "\(isCache ? "Xcode build cache path" : "path to delete") · \(isOutside ? "outside" : "inside") the worktree",
                    destructive: !isCache))
        }
        return Self(
            command: command, risk: allCaches ? .routine : .irreversible,
            action: allCaches
                ? "delete Xcode's build cache" : "delete \(paths.count == 1 ? "this path" : "these paths")",
            reason: outside
                ? "The command names a path outside the worktree." : "The command names paths inside the worktree.",
            consequence: allCaches
                ? "Rebuilt on the next build. Contents and symbolic links have not been inspected."
                : "Can't be undone from here. Files are deleted directly, without moving them to Trash. Contents and symbolic links have not been inspected.",
            parts: parts, suggestedCommand: nil)
    }

    private static func part(
        _ token: ApprovalCommandWords.Token, _ explanation: String, destructive: Bool = false
    ) -> Part {
        Part(range: token.range, explanation: explanation, destructive: destructive)
    }
}
