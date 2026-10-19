import AIInstructions
import Foundation
import Git
import GitHub

/// Runs a purpose's real generator on the sample task with some instructions, so the user sees
/// what they change before a real task does. On-device purposes write their result; agent purposes
/// show the message the agent would get, since running an agent for a preview would spend the
/// user's usage.
enum AIInstructionPreviewer {
    enum Output: Equatable {
        /// What the on-device model wrote.
        case generated(String)
        /// What the agent would be sent.
        case prompt(String)
    }

    enum Failure: LocalizedError {
        /// Apple Intelligence can't run on this Mac right now, and why.
        case unavailable(String)
        case nothingWritten

        var errorDescription: String? {
            switch self {
            case .unavailable(let reason): reason
            case .nothingWritten: "The model didn't write anything for the sample."
            }
        }
    }

    /// `branchPrefix` is the prefix the user's settings give new branches. `project` is the project
    /// being previewed for, whose instructions apply to the other purposes a generator uses.
    static func preview(
        _ purpose: AIInstructionPurpose, text: String, branchPrefix: String, project: URL? = nil
    ) async throws -> Output {
        let addition = AIInstructionAddition(text)
        if purpose.generator == .onDevice, let reason = PullRequestDrafter.unavailableReason {
            throw Failure.unavailable(reason)
        }
        let samples = AIInstructionSamples.self
        switch purpose {
        case .title:
            let request = TitleRequest(
                projectName: samples.projectName, prompt: samples.request, instructions: addition)
            return try await generated(OnDeviceTitler().title(for: request))
        case .branchName:
            let name = try await BranchNameDrafter.suggest(
                title: samples.title, request: samples.request, prefix: branchPrefix, instructions: addition)
            return try generated(name)
        case .commitMessage:
            return try await generated(
                CommitMessageDrafter().draft(
                    patch: samples.patch, files: samples.files, style: CommitStyle(subjects: samples.subjects),
                    instructions: addition))
        case .commitGrouping:
            let planner = SmartCommitPlanner(
                messageInstructions: AIInstructionsStore.shared.addition(for: .commitMessage, in: project),
                groupingInstructions: addition)
            let plan = try await planner.plan(
                files: GitCommitFile.files(from: samples.files), patch: samples.patch,
                style: CommitStyle(subjects: samples.subjects))
            return try generated(
                plan.groups.map { group in
                    let files = group.paths.map { "  \(URL(filePath: $0).lastPathComponent)" }
                    return ([group.message.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""] + files)
                        .joined(separator: "\n")
                }
                .joined(separator: "\n\n"))
        case .pullRequest:
            var title = ""
            var body = ""
            let prompt = PullRequestDraftPrompt(
                head: "fix-double-charge", base: "main", commits: samples.commits, diff: samples.patch)
            try await PullRequestDrafter.draft(prompt, instructions: addition) { newTitle, newBody in
                if let newTitle { title = newTitle }
                if let newBody { body = newBody }
            }
            return try generated([title, body].filter { !$0.isEmpty }.joined(separator: "\n\n"))
        case .reviewRequest:
            var prompt = samples.reviewRequest
            prompt.instructions = addition
            return .prompt(prompt.text)
        case .pullRequestQuestions:
            let source = samples.pullRequestSource
            return .prompt(
                PullRequestAskPrompt.opening(
                    samples.question, context: PullRequestAskContext(source), source: source, adding: addition))
        }
    }

    private static func generated(_ text: String?) throws -> Output {
        let text = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { throw Failure.nothingWritten }
        return .generated(text)
    }
}
