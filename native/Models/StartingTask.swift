import ACP
import Foundation
import Observation

/// A task the user just asked for, from the click until its session exists. The sidebar lists it
/// at once ("Starting…") and its composer takes a draft while the workspace is made and the agent
/// starts, which on a large repository can take a while. When the session is ready the draft moves
/// over, and goes out if the user already sent it. A failure stays on the task with what went
/// wrong, so Retry keeps the draft and the workspace already made.
@Observable
final class StartingTask: Identifiable {
    /// What the task is waiting for, in the order it shows. The workspace and the agent are made at
    /// the same time; the step is whichever still holds the task up.
    enum Step: Equatable {
        /// Making the task's worktree or branch.
        case preparingWorkspace
        /// Waiting for the agent's process.
        case startingAgent
        /// Asking the agent for the session.
        case openingSession
    }

    struct Failure: Equatable {
        /// What failed, as a title: "Couldn't create the task's worktree".
        let title: String
        /// Why, in the tool's own words.
        let message: String
        /// The agent wants the user to sign in first; the window's sign-in prompt is showing.
        var needsSignIn = false
        /// The failed process must restart before this task can be tried again.
        var needsRestart = false
        /// No worktree can be made (the repository has no commits), but the task can run in the
        /// project folder instead.
        var canUseProjectFolder = false
    }

    /// Stands in for the session's key in the sidebar and the selection until the session exists.
    let id: SessionKey
    let project: Project.ID
    let agent: AgentDefinition
    /// The user chose the agent, rather than taking the project's or the one used last; only then
    /// does it become the one new tasks start with.
    let isAgentPicked: Bool
    let startedAt = Date.now
    /// What the provider makes for the task ("Creating a worktree"), for the first step's label.
    let workspaceLabel: String
    /// Where the task runs: this Mac, or a paired host (AppModel+HostsStarting.swift).
    var device = SessionDevice.thisMac
    /// The task's folder, once made; a retry reuses it.
    var folder: URL?
    var ownsWorkspace = false
    var isAgentReady = false
    var failure: Failure?
    var draft = ""
    var attachments: [PromptAttachment] = []
    var configChoices: [String: String] = [:]
    var workspaceChoice: TaskWorkspaceChoice?
    var usesComposePresentation = false
    /// The user sent the draft; it goes out as soon as the session can take it.
    var isSendRequested = false
    /// The finished task's destination for a background start's Open action.
    var openedSession: SessionKey?
    /// Asks the starting composer to take focus; it clears it once it has.
    var wantsComposerFocus = true
    /// The user discarded the task while it was starting.
    @ObservationIgnored var isDiscarded = false

    init(project: Project.ID, agent: AgentDefinition, isAgentPicked: Bool, workspaceLabel: String) {
        id = SessionKey(agent: agent.id, id: SessionID("native-starting-\(UUID().uuidString)"))
        self.project = project
        self.agent = agent
        self.isAgentPicked = isAgentPicked
        self.workspaceLabel = workspaceLabel
    }

    var step: Step {
        if folder == nil { return .preparingWorkspace }
        if !isAgentReady { return .startingAgent }
        return .openingSession
    }

    /// The step as a line: "Creating a worktree", "Starting Codex", "Opening the session".
    var stepLabel: String {
        switch step {
        case .preparingWorkspace: workspaceLabel
        case .startingAgent: "Starting \(agent.displayName)"
        case .openingSession: "Opening the task"
        }
    }
}
