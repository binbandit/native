import Foundation

/// The user's own instructions for one purpose, as they're added to a feature's built-in prompt.
/// They always come after the built-in prompt and say they yield to its rules, so they can change
/// the style and content of what's written but never the format the feature parses.
public struct AIInstructionAddition: Hashable, Sendable {
    /// The most of the user's text that's sent. On-device models have small context windows, and
    /// every character here is one less of the diff or request.
    public static let maximumLength = 1_000

    /// The user's text, trimmed and capped.
    public let text: String

    /// Nil when there's nothing to add.
    public init?(_ text: String?) {
        let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            .replacing(/\n{3,}/, with: "\n\n")
        guard !trimmed.isEmpty else { return nil }
        self.text = String(trimmed.prefix(Self.maximumLength)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `builtIn` with these instructions after it. `topic` says what they're about when a prompt
    /// carries more than one addition ("commit messages").
    public func applied(to builtIn: String, about topic: String? = nil) -> String {
        let heading = "More instructions from the user" + (topic.map { " about \($0)" } ?? "")
        // The user's own text can't close the tag early, so the heading's precedence holds for all of it.
        let body = text.replacingOccurrences(of: Self.close, with: "<\\/user_instructions>")
        return builtIn + "\n\n" + heading + Self.precedence + "\n" + Self.open + "\n" + body + "\n" + Self.close
    }

    /// `builtIn`, with `addition` after it when there is one.
    public static func applying(
        _ addition: AIInstructionAddition?, to builtIn: String, about topic: String? = nil
    ) -> String {
        addition?.applied(to: builtIn, about: topic) ?? builtIn
    }

    private static let precedence =
        ". Follow them too, but where one conflicts with a required format or rule above, the requirement wins."
    private static let open = "<user_instructions>"
    private static let close = "</user_instructions>"
}
