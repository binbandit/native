import Foundation

/// A part of Native that writes something with AI, which the user can give instructions of their
/// own. The raw values are stable: settings and the organization's policy store instructions by them.
public enum AIInstructionPurpose: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    /// Task titles in the sidebar, from the first message.
    case title
    /// A new task's branch, named once the task has a title.
    case branchName
    /// Drafted commit messages, also those of a smart commit's commits.
    case commitMessage
    /// How a smart commit splits changes into commits.
    case commitGrouping
    /// A pull request's drafted title and description.
    case pullRequest
    /// "Ask an Agent" on lines of a pull request.
    case reviewRequest
    /// The private "Ask about this pull request" conversation.
    case pullRequestQuestions

    /// What writes the text.
    public enum Generator: Sendable {
        /// Apple's on-device model, on this Mac.
        case onDevice
        /// The task's coding agent, whose prompt gets the instructions.
        case agent
    }

    public var id: Self { self }

    public var generator: Generator {
        switch self {
        case .title, .branchName, .commitMessage, .commitGrouping, .pullRequest: .onDevice
        case .reviewRequest, .pullRequestQuestions: .agent
        }
    }
}
