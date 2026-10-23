import AIInstructions

/// How Settings names each purpose and what it shows as an example.
extension AIInstructionPurpose {
    var plainlyCopy: SettingsPlainlyCopy {
        switch self {
        case .title: .taskTitles
        case .branchName: .branchNames
        case .commitMessage: .commitMessages
        case .commitGrouping: .commitGrouping
        case .pullRequest: .prDrafts
        case .reviewRequest: .askLines
        case .pullRequestQuestions: .askPR
        }
    }

    var title: String {
        switch self {
        case .title: "Task titles"
        case .branchName: "Branch names"
        case .commitMessage: "Commit messages"
        case .commitGrouping: "Smart commit grouping"
        case .pullRequest: "Pull request drafts"
        case .reviewRequest: "Ask an Agent"
        case .pullRequestQuestions: "Ask about a pull request"
        }
    }

    /// What the instructions affect, in a sentence.
    var summary: String {
        switch self {
        case .title: "How new tasks are named in the sidebar, from your first message."
        case .branchName:
            "What a new task's branch is called once the task has a title. Without instructions, it's the title in kebab case."
        case .commitMessage: "Messages drafted in the commit popover and for each commit of a smart commit."
        case .commitGrouping: "How a smart commit splits your changes into commits."
        case .pullRequest: "The title and description drafted when you create a pull request."
        case .reviewRequest: "Added to what the agent gets when you ask it about lines of a pull request."
        case .pullRequestQuestions: "Added to what the agent gets when you ask about a pull request in its panel."
        }
    }

    /// An example instruction, shown in the empty field.
    var example: String {
        switch self {
        case .title: "Keep ticket keys like ABC-123 at the start of the title"
        case .branchName: "Use Jira keys like ABC-123 at the start of branch names"
        case .commitMessage: "Write commit messages in the imperative, no emoji"
        case .commitGrouping: "Keep database migrations in a commit of their own"
        case .pullRequest: "End the description with a Testing section"
        case .reviewRequest: "Run the tests for files you change before you finish"
        case .pullRequestQuestions: "Answer in two or three sentences, then the details"
        }
    }

    /// More words that find the purpose in Settings search.
    var keywords: [String] {
        switch self {
        case .title: ["title", "name", "sidebar"]
        case .branchName: ["branch", "jira", "prefix", "worktree"]
        case .commitMessage: ["commit", "message", "conventional"]
        case .commitGrouping: ["smart commit", "split", "group"]
        case .pullRequest: ["pull request", "pr", "description"]
        case .reviewRequest: ["review", "ask an agent", "pull request"]
        case .pullRequestQuestions: ["ask", "question", "pull request"]
        }
    }

    /// Where the row reveals in Settings search.
    var settingsRowID: SettingsRowID {
        SettingsRowID("aiInstructions.\(rawValue)")
    }
}
