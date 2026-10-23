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
            homeDirectory: approvalHome, isAvailable: session.phase == .prompting,
            onChoose: { option in Task { await session.chooseApproval(option, for: call) } },
            onInstruct: { text in try await session.instructInstead(text, for: call) }
        )
        .id(call)
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
