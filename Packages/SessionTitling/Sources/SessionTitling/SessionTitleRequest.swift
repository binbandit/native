import AIInstructions
import Foundation

/// What a task's title is written from: its first message, the project it runs in, and the user's
/// own instructions for titles (Settings ▸ AI Instructions), which a generator adds after its own
/// rules so they change a title's style but never its format.
public struct SessionTitleRequest: Hashable, Sendable {
    public var projectName: String
    /// The user's first message in the session.
    public var prompt: String
    public var instructions: AIInstructionAddition?
    /// The titles of the project's other live tasks, which this one should be told apart from.
    public var otherTitles: [String]

    public init(
        projectName: String, prompt: String, instructions: AIInstructionAddition? = nil, otherTitles: [String] = []
    ) {
        self.projectName = projectName
        self.prompt = prompt
        self.instructions = instructions
        self.otherTitles = otherTitles
    }

    /// The request for a task's first message in `folder`. A message with only attachments is
    /// about what it attaches. A task in its own worktree is named for the project it's a
    /// worktree of, not for the worktree's folder.
    public init(firstMessage text: String, attachmentNames: [String], in folder: URL) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(
            projectName: SessionTitleRules.projectFolder(of: folder).lastPathComponent,
            prompt: text.isEmpty ? attachmentNames.joined(separator: ", ") : text)
    }

    /// What the model is asked: the built-in prompt, and the titles to tell this one apart from.
    var modelPrompt: String {
        let base = SessionTitlePrompt.prompt(projectName: projectName, request: prompt)
        guard !otherTitles.isEmpty else { return base }
        let titles = otherTitles.map { "\"\($0)\"" }.joined(separator: ", ")
        return base
            + "\nOther tasks in this project are titled \(titles). Title this one so it can be told apart from them."
    }
}
