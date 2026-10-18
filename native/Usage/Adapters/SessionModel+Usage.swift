import ACP
import Foundation

extension SessionModel: LimitResumable {
    var resumeReadiness: ResumeReadiness {
        // A subagent takes work only from its parent, so there's never anything to resume.
        guard acceptsPrompts else { return .busy }
        switch phase {
        case .idle: return isRunningHiddenCommand ? .unavailable : .ready
        case .prompting: return .busy
        case .loading, .disconnected: return .unavailable
        }
    }

    func resume(with prompt: String) async {
        _ = try? await submit(prompt, .queue)
    }
}

extension SessionModel: ContextReporting {
    var contextKey: SessionKey {
        key
    }

    var canReportContext: Bool {
        acceptsPrompts && advertises("context")
    }

    var isIdleForContext: Bool {
        phase == .idle && !isRunningHiddenCommand
    }

    /// Whether the agent lists `command` among its slash commands.
    func advertises(_ command: String) -> Bool {
        availableCommands.contains { $0.name == command }
    }
}
