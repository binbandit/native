import Foundation

/// What a question's context carried, in counts, so the panel can say exactly what the agent saw
/// and what it has to look up. Saved with the conversation, so a reopened one still says it.
public struct PullRequestAskInclusion: Sendable, Hashable, Codable {
    public var hasDescription = true
    public var descriptionTrimmed = false
    public var comments = 0
    public var commentsLoaded = 0
    /// Whether the conversation goes on past what Native loaded.
    public var conversationContinues = false
    public var threads = 0
    public var threadsLoaded = 0
    public var threadsTotal = 0
    public var files = 0
    public var filesListed = 0
    /// Files whose diff is in the context itself.
    public var filesInDiff = 0
    /// Files whose diff Native loaded, all of them saved for the agent to read.
    public var filesWithPatch = 0
    /// Files GitHub has no diff for: binary, too large to show, or only renamed.
    public var filesWithoutPatch = 0
    public var additions = 0
    public var deletions = 0

    public init() {}

    /// Whether everything Native knows went into the context, so nothing needs looking up.
    public var isWhole: Bool {
        leftOut.isEmpty
    }

    /// One sentence for the context chip: "The description, 6 comments, 3 review threads and the
    /// whole diff (12 files, +340 -22)."
    public var summary: String {
        var parts = [
            hasDescription
                ? (descriptionTrimmed ? "the start of the description" : "the description") : "no description"
        ]
        if commentsLoaded > 0 {
            parts.append(
                comments == commentsLoaded
                    ? Self.counted(comments, "comment") : "\(comments) of \(Self.counted(commentsLoaded, "comment"))")
        }
        if threadsTotal > 0 {
            parts.append(
                threads == threadsTotal
                    ? Self.counted(threads, "review thread")
                    : "\(threads) of \(Self.counted(threadsTotal, "review thread"))")
        }
        let size = "+\(additions) -\(deletions)"
        if files == 0 {
            parts.append("no changed files")
        } else if filesInDiff == filesWithPatch, filesWithPatch + filesWithoutPatch == files {
            parts.append("the whole diff (\(Self.counted(files, "file")), \(size))")
        } else {
            parts.append("the diff of \(filesInDiff) of \(Self.counted(files, "file")) (\(size))")
        }
        let list = Self.list(parts)
        return list.prefix(1).uppercased() + list.dropFirst() + "."
    }

    /// What didn't fit or wasn't loaded, one sentence each, saying where the agent finds it.
    public var leftOut: [String] {
        var notes: [String] = []
        if descriptionTrimmed {
            notes.append("The description was cut short; the agent has the rest in its saved copy.")
        }
        if comments < commentsLoaded {
            notes.append(
                "\(Self.counted(commentsLoaded - comments, "earlier comment")) didn't fit; the agent has them in its saved copy."
            )
        }
        if conversationContinues {
            notes.append("The conversation is longer than Native loaded; later comments are only on GitHub.")
        }
        if threads < threadsLoaded {
            notes.append(
                "\(Self.counted(threadsLoaded - threads, "review thread")) didn't fit; the agent has them in its saved copy."
            )
        }
        if threadsLoaded < threadsTotal {
            notes.append("Native didn't load \(Self.counted(threadsTotal - threadsLoaded, "review thread")).")
        }
        if filesInDiff < filesWithPatch {
            notes.append(
                "Diffs of \(Self.counted(filesWithPatch - filesInDiff, "file")) didn't fit; the agent reads them from its saved copy when a question needs them."
            )
        }
        let notLoaded = files - filesWithPatch - filesWithoutPatch
        if notLoaded > 0 {
            notes.append(
                "Native didn't load the diffs of \(Self.counted(notLoaded, "file")); the agent can ask gh for them.")
        }
        return notes
    }

    static func counted(_ count: Int, _ noun: String) -> String {
        "\(count.formatted()) \(count == 1 ? noun : noun + "s")"
    }

    static func list(_ parts: [String]) -> String {
        guard parts.count > 1, let last = parts.last else { return parts.first ?? "" }
        return parts.dropLast().joined(separator: ", ") + " and " + last
    }
}
