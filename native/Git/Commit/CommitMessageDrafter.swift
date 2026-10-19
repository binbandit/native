import AIInstructions
import Foundation
import FoundationModels
import Git

/// Drafts commit messages with Apple's on-device model: private and free, and good enough to
/// summarize a diff when it's shown the right slice of it. The model's context is small (about
/// 4k tokens), so the patch is trimmed to fit, every file keeping a share.
struct CommitMessageDrafter {
    @Generable
    struct Draft {
        @Guide(
            description:
                "The commit subject: one line under 72 characters, imperative mood (\"Add\", \"Fix\", not \"Added\"), no trailing period."
        )
        var subject: String
        @Guide(
            description:
                "An optional body explaining why the change was made, wrapped at 72 characters. Leave it empty for small, self-explanatory changes, unless the user's instructions ask for one."
        )
        var body: String?
    }

    static var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    /// Tokens kept free for the generated message.
    private static let responseTokens = 320
    /// A rough first guess at characters per token for code, refined by measuring.
    private static let charactersPerToken = 3

    /// A message for the diff, in the repository's `style`, following the user's `instructions`
    /// for commit messages too.
    func draft(
        patch: String, files: [FileChange], style: CommitStyle, instructions addition: AIInstructionAddition? = nil
    ) async throws -> String {
        let model = SystemLanguageModel.default
        let instructions = CommitPrompts.message(style: style, adding: addition)
        let fixed =
            try await model.tokenCount(for: Instructions(instructions)) + model.tokenCount(for: Draft.generationSchema)
        var budget = max(model.contextSize - fixed - Self.responseTokens, 256) * Self.charactersPerToken

        for _ in 0..<4 {
            let prompt = Self.prompt(patch: PatchTrimmer.trim(patch, toCharacters: budget), files: files)
            let tokens = try await model.tokenCount(for: prompt)
            let available = model.contextSize - fixed - Self.responseTokens
            guard tokens <= available else {
                budget = budget * available / max(tokens, 1) * 9 / 10
                continue
            }
            do {
                let session = LanguageModelSession(model: model, instructions: instructions)
                let response = try await session.respond(
                    to: prompt,
                    generating: Draft.self,
                    options: GenerationOptions(temperature: 0.3, maximumResponseTokens: Self.responseTokens)
                )
                return Self.format(response.content)
            } catch LanguageModelError.contextSizeExceeded {
                budget /= 2
            }
        }
        throw CocoaError(
            .featureUnsupported,
            userInfo: [NSLocalizedDescriptionKey: "The changes are too large to summarize on this Mac."])
    }

    private static func prompt(patch: String, files: [FileChange]) -> String {
        let list = Set(files.map(\.path)).sorted().joined(separator: "\n")
        return "Files changed:\n\(list)\n\nDiff:\n\(patch)"
    }

    private static func format(_ draft: Draft) -> String {
        let subject = draft.subject
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".\"'`"))
        let body = draft.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return body.isEmpty ? subject : "\(subject)\n\n\(body)"
    }
}
