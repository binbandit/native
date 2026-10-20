import AIInstructions
import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Titles tasks with Apple's on-device model: private, free, and fast enough to name a task as soon
/// as it starts. The app and the host run the same one, so a title reads the same wherever it was
/// written. Where the model can't run (an older OS, Apple Intelligence off, another platform) it
/// writes nothing and says so by returning nil.
public struct OnDeviceTitleGenerator: SessionTitleGenerator {
    public init() {}

    /// Whether the model can run here now.
    public static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }

    public func title(for request: SessionTitleRequest) async throws -> String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *), SystemLanguageModel.default.isAvailable {
            let session = LanguageModelSession(
                instructions: SessionTitlePrompt.instructions(adding: request.instructions))
            // Greedy, so the same message gets the same title, and only what differs tells tasks apart.
            let response = try await session.respond(
                to: request.modelPrompt, generating: Title.self, options: GenerationOptions(samplingMode: .greedy))
            return SessionTitleRules.cleaned(response.content.title).map {
                SessionTitleRules.sentenceCase($0, keeping: request.prompt)
            }
        }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
extension OnDeviceTitleGenerator {
    /// What the model writes, guided as `@Generable` would guide it. Written out by hand: the macro
    /// needs full Xcode to expand, and the host builds with the command line tools too.
    @available(macOS 26.0, iOS 26.0, *)
    struct Title: Generable {
        var title: String

        static var generationSchema: GenerationSchema {
            GenerationSchema(
                type: Self.self,
                properties: [GenerationSchema.Property(name: "title", description: guide, type: String.self)])
        }

        init(_ content: GeneratedContent) throws {
            title = try content.value(forProperty: "title")
        }

        var generatedContent: GeneratedContent {
            GeneratedContent(properties: ["title": title])
        }

        private static let guide =
            "A 2 to 6 word title naming the task the user asked for and what it's about (the file, function, feature or goal), in sentence case, like a short commit subject. Imperative when the user asked for a change (\"Add docstring to greet\"), a noun phrase for questions (\"Auth middleware overview\"). Never only a generic action like \"Run shell command\" or \"Fix bug\". No quotes, no trailing punctuation, no filler like \"task\" or \"request\"."
    }
}
#endif
