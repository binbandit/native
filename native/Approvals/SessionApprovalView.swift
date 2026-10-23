import ACP
import SwiftUI

struct SessionApprovalView: View {
    let session: SessionModel
    let call: ToolCallState
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        AnnotatedApprovalView(
            call: call, agentName: session.agentName,
            workingDirectory: session.cwd.path,
            homeDirectory: approvalHome, isAvailable: isAvailable,
            focusRequested: session.wantsComposerFocus, didFocus: { session.wantsComposerFocus = false },
            onChoose: { option in Task { await session.chooseApproval(option, for: call) } },
            onInstruct: instruct
        )
        .environment(\.accessibilityReduceMotion, effectiveReduceMotion)
        .id(call)
    }

    private var isAvailable: Bool {
        #if DEBUG
        if ApprovalPreviewOverride.current == .reconnecting { return false }
        #endif
        return session.phase == .prompting
    }

    private var effectiveReduceMotion: Bool {
        #if DEBUG
        if ApprovalPreviewOverride.current == .reducedMotion { return true }
        #endif
        return reduceMotion
    }

    private func instruct(_ text: String) async throws {
        #if DEBUG
        if ApprovalPreviewOverride.current == .instructionFailure { throw CocoaError(.fileWriteNoPermission) }
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
