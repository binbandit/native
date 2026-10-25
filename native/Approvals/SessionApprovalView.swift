import ACP
import SwiftUI

struct SessionApprovalView: View {
    let session: SessionModel
    let call: ToolCallState
    @Environment(AppModel.self) private var app

    var body: some View {
        AnnotatedApprovalView(
            call: call, agentName: session.agentName,
            workingDirectory: session.cwd.path,
            homeDirectory: approvalHome, knowledge: app.plugins.commandKnowledge, isAvailable: isAvailable,
            forceReducedMotion: forceReducedMotion,
            focusRequested: session.wantsComposerFocus, didFocus: { session.wantsComposerFocus = false },
            planEntries: call.kind == .switchMode ? session.state.currentTurnPlan : [],
            onChoose: { option in Task { await session.chooseApproval(option, for: call) } },
            onInstruct: instruct
        )
        .id(call)
    }

    private var isAvailable: Bool {
        #if DEBUG
        if ApprovalPreviewOverride.current == .reconnecting { return false }
        #endif
        return session.phase == .prompting
    }

    private var forceReducedMotion: Bool {
        #if DEBUG
        if ApprovalPreviewOverride.current == .reducedMotion { return true }
        #endif
        return false
    }

    private func instruct(_ text: String) async throws {
        #if DEBUG
        if ApprovalPreviewOverride.failNextInstruction() {
            try await Task.sleep(for: .seconds(1))
            throw CocoaError(.fileWriteNoPermission)
        }
        #endif
        try await session.instructInstead(text, for: call)
    }

    // A remote task's tilde belongs to its host, never to this Mac's home directory.
    private var approvalHome: String? {
        guard app.device(of: session.root.key) == .thisMac else { return nil }
        return NSHomeDirectory()
    }
}

#if DEBUG
#Preview("Session approval") {
    ApprovalPreviewFixtures.composer()
}
#endif
