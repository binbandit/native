import Foundation
import FoundationModels
import Git

/// Splits working changes into logical commits with Apple's on-device model, each with a message
/// in the repository's style. Files are numbered in the prompt and the model answers with numbers,
/// which it gets right far more often than paths. Without the model, changes group by folder.
struct SmartCommitPlanner {
    @Generable
    struct PlanDraft {
        @Guide(description: "The commits, in the order to make them, so each builds on the ones before. Between 1 and 6; one commit is fine for one change.")
        var commits: [CommitDraft]
    }

    @Generable
    struct CommitDraft {
        @Guide(description: "The commit subject: one line under 72 characters, imperative mood, no trailing period.")
        var subject: String
        @Guide(description: "An optional body saying why, wrapped at 72 characters. Empty for self-explanatory commits.")
        var body: String?
        @Guide(description: "The numbers of this commit's files, from the numbered list. Every file goes in exactly one commit.")
        var files: [Int]
    }

    static var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    /// Tokens kept free for the plan.
    private static let responseTokens = 900
    private static let charactersPerToken = 3

    func plan(files: [GitCommitFile], patch: String, style: CommitStyle) async throws -> CommitPlan {
        let paths = files.map(\.path)
        guard Self.isAvailable, files.count > 1 else { return Self.fallback(paths) }
        let model = SystemLanguageModel.default
        let instructions = Self.instructions(for: style)
        let fixed =
            try await model.tokenCount(for: Instructions(instructions)) + model.tokenCount(for: PlanDraft.generationSchema)
        let available = max(model.contextSize - fixed - Self.responseTokens, 256)
        var budget = available * Self.charactersPerToken
        for _ in 0..<4 {
            let prompt = Self.prompt(files: files, patch: PatchTrimmer.trim(patch, toCharacters: budget))
            let tokens = try await model.tokenCount(for: prompt)
            guard tokens <= available else {
                budget = budget * available / max(tokens, 1) * 9 / 10
                continue
            }
            do {
                let session = LanguageModelSession(model: model, instructions: instructions)
                let response = try await session.respond(
                    to: prompt, generating: PlanDraft.self,
                    options: GenerationOptions(temperature: 0.2, maximumResponseTokens: Self.responseTokens))
                let proposal = response.content.commits.map { draft in
                    (message: Self.message(draft), paths: draft.files.compactMap { paths.indices.contains($0 - 1) ? paths[$0 - 1] : nil })
                }
                return CommitPlan.reconciling(
                    proposal, changedPaths: paths, leftoverMessage: style.isConventional ? "chore: other changes" : "Other changes")
            } catch LanguageModelError.contextSizeExceeded {
                budget /= 2
            }
        }
        return Self.fallback(paths)
    }

    /// One commit per top-level folder.
    static func fallback(_ paths: [String]) -> CommitPlan {
        CommitPlan.byFolder(paths)
    }

    private static func instructions(for style: CommitStyle) -> String {
        var lines = [
            "You split a developer's uncommitted changes into a few logical commits, the way a careful engineer would: one coherent change per commit, with tests next to the code they test. Base everything on the diff; never invent details."
        ]
        if style.isConventional {
            var convention = "Subjects use Conventional Commits: \"type(scope): summary\" with type one of feat, fix, refactor, docs, test, chore, perf, style, build, ci."
            if !style.commonScopes.isEmpty {
                convention += " Scopes this repository uses: \(style.commonScopes.joined(separator: ", "))."
            }
            lines.append(convention)
        } else {
            lines.append("Subjects match the repository's style: a short sentence-case summary, no type prefix.")
        }
        if !style.examples.isEmpty {
            lines.append(
                "Recent subjects in this repository. Match their style only; describe the diff, not these:\n"
                    + style.examples.map { "- \($0)" }.joined(separator: "\n"))
        }
        return lines.joined(separator: "\n\n")
    }

    private static func prompt(files: [GitCommitFile], patch: String) -> String {
        let list = files.enumerated().map { index, file in
            "\(index + 1). \(file.path) (+\(file.stats.additions) -\(file.stats.deletions))"
        }
        return "Files:\n\(list.joined(separator: "\n"))\n\nDiff:\n\(patch)"
    }

    private static func message(_ draft: CommitDraft) -> String {
        let subject = draft.subject.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".\"'`"))
        let body = draft.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return body.isEmpty ? subject : "\(subject)\n\n\(body)"
    }
}
