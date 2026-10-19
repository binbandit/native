import AIInstructions
import FoundationModels
import Git

/// Names a task's branch with Apple's on-device model, for users who gave instructions for branch
/// names ("prefix with brayden/", "start with the Jira key"). The answer is cleaned into a name git
/// accepts; when the model isn't available or leaves nothing usable, the caller names the branch
/// from the title as usual.
enum BranchNameDrafter {
    @Generable
    struct Suggestion {
        @Guide(description: "The branch name alone, like fix-login-redirect: letters, digits, hyphens and slashes.")
        var name: String
    }

    /// `prefix` is the one the user's settings give new branches, which the model starts with
    /// unless the instructions say otherwise.
    static func suggest(
        title: String, request: String?, prefix: String, instructions: AIInstructionAddition?
    ) async throws -> String? {
        guard SystemLanguageModel.default.isAvailable else { return nil }
        let session = LanguageModelSession(
            instructions: BranchNaming.suggestionInstructions(prefix: prefix, adding: instructions))
        let response = try await session.respond(
            to: BranchNaming.suggestionPrompt(title: title, request: request), generating: Suggestion.self,
            options: GenerationOptions(temperature: 0.2, maximumResponseTokens: 60))
        return BranchNaming.name(fromSuggestion: response.content.name)
    }
}
