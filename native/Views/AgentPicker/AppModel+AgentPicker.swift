#if NATIVE_AGENT_PICKER_WIP
import Foundation

// New Session With… (⌥⌘N): the agents it offers and what choosing one does. It lists the agents the
// sidebar's New Session menu and Home's cards do, in the same order, and reads each one's state from
// the same fold (`availability(of:)`), so the three never disagree.
extension AppModel {
    /// The agents the picker offers for a new session in the current project.
    func agentPickerOptions() -> [AgentPickerOption] {
        let defaultID = defaultAgent(in: currentProject)?.id
        let isFolderMissing = agentPickerBlocker != nil
        return agents.map { runtime in
            let agent = runtime.agent
            let availability = availability(of: agent)
            let canSignIn = !runtime.authMethods.isEmpty
            let choice: AgentPickerOption.Choice? =
                switch availability {
                case .ready, .starting: .startSession
                case .needsSignIn where canSignIn: .signInThenStart
                case .needsSignIn, .signingIn, .notInstalled, .disabled, .failed: nil
                }
            let remedy: AgentPickerOption.Remedy? =
                switch availability {
                case .notInstalled: .checkAgain
                // Signed in from a terminal, it picks the login up once it starts again.
                case .needsSignIn where !canSignIn, .failed: .restart
                case .ready, .starting, .needsSignIn, .signingIn, .disabled: nil
                }
            return AgentPickerOption(
                agent: agent,
                status: AgentPickerStatus(availability),
                choice: isFolderMissing ? nil : choice,
                reason: availability.guidance(for: agent.manifest),
                remedy: remedy,
                isDefault: agent.id == defaultID)
        }
    }

    /// Why no agent can start a session in the current project right now: its folder is gone.
    var agentPickerBlocker: ProjectProblem? {
        currentProject.flatMap { missingFolder(of: $0.id) }
    }

    /// Starts a session with the agent chosen in the picker, and closes it. An agent that wants a
    /// sign-in asks for it first; the sign-in prompt starts the session once it's done.
    func chooseAgentForNewSession(_ agent: AgentDefinition.ID) async {
        isChoosingAgent = false
        if let runtime = runtime(agent), runtime.needsSignIn, !runtime.authMethods.isEmpty {
            signInPrompt = agent
        } else {
            await newSession(with: agent)
        }
    }
}
#endif
