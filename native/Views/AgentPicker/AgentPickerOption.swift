#if NATIVE_AGENT_PICKER_WIP
import SwiftUI

/// One agent as the agent picker offers it: who it is, where it stands, why it can't start a session
/// when it can't, and the fix. The app builds these from the agents' runtimes
/// (`AppModel.agentPickerOptions()`); previews build them from fixtures.
struct AgentPickerOption: Identifiable {
    /// What choosing the agent does.
    enum Choice: Equatable {
        /// Starts the session, after the agent itself if it's idle or still starting.
        case startSession
        /// Asks the user to sign in, then starts the session.
        case signInThenStart
    }

    /// The one fix for an agent that can't start a session. Both start it again, which looks for its
    /// command again first.
    enum Remedy: Equatable {
        /// After the user installs it.
        case checkAgain
        /// After it stopped, or the user signed in from a terminal.
        case restart

        var title: String {
            switch self {
            case .checkAgain: "Check Again"
            case .restart: "Restart"
            }
        }

        /// What VoiceOver says while it runs: "Checking for Pi".
        var progressTitle: String {
            switch self {
            case .checkAgain: "Checking for"
            case .restart: "Restarting"
            }
        }

        /// The button's title with the agent in it, for VoiceOver: "Check Again for Pi".
        func accessibilityTitle(for name: String) -> String {
            switch self {
            case .checkAgain: "Check Again for \(name)"
            case .restart: "Restart \(name)"
            }
        }
    }

    let agent: AgentDefinition
    let status: AgentPickerStatus
    /// What Return or a click does with it; nil while it can't start a session, which dims it.
    let choice: Choice?
    /// What's wrong and what to do about it, under the name; nil while the agent is fine.
    let reason: String?
    /// The one action that gets it going again, offered beside it.
    let remedy: Remedy?
    /// The agent ⌘N starts with, which the picker opens on.
    let isDefault: Bool

    var id: AgentDefinition.ID { agent.id }
    var name: String { agent.displayName }
}
#endif
